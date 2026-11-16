//
//  FeedPlaybackCoordinator.swift
//  IOS Frontend
//
//  The feed's one player.
//

import AVFoundation
import Network
import Observation
import SwiftUI

/// Owns the single `AVPlayer` a feed is allowed, and moves it between cards
/// as `FeedPlaybackPolicy` says.
///
/// The cards tell it how visible they are and the feed tells it how it is
/// being scrolled; it asks the policy for a plan and makes the player match.
/// Every decision is the policy's. What lives here is only what needs a
/// player: starting and stopping it, getting one clip ready behind it, and
/// telling the measurement what actually played.
///
/// One player, reused. A player per card is what makes a feed of clips slow
/// and heavy: each holds decoders and buffers whether or not anyone is
/// watching it.
@MainActor
@Observable
final class FeedPlaybackCoordinator {
    /// The feed's clips in the order they are drawn, with their sources.
    struct Clip: Equatable {
        var postID: Int
        var url: URL
        var durationMilliseconds: Int
    }

    /// The post whose clip the player is showing, for a card to know whether
    /// to draw the player or its poster.
    private(set) var activePostID: Int?
    private(set) var isBuffering = false
    /// Posts whose clip would not play, so the card can say so.
    private(set) var failedPostIDs: Set<Int> = []
    /// Sound is off until the reader turns it on, and then stays as they
    /// left it for the rest of the session.
    var isMuted = true { didSet { player.isMuted = isMuted } }

    let player = AVPlayer()

    @ObservationIgnored private var clips: [Clip] = []
    @ObservationIgnored private var visibility: [Int: Double] = [:]
    @ObservationIgnored private var startedByReader: Int?
    @ObservationIgnored private var pausedByReader = false
    @ObservationIgnored private var isScrollingRapidly = false
    @ObservationIgnored private var isFeedActive = true
    @ObservationIgnored private var settings = FeedPlaybackSettings()
    @ObservationIgnored private var prepared: (postID: Int, item: AVPlayerItem)?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var lastOffset: (y: CGFloat, at: TimeInterval)?
    /// Told what played, for the measurement. Set by the feed.
    @ObservationIgnored var report: (Int, SocialStore.PlaybackEvent) -> Void = { _, _ in }

    init() {
        player.isMuted = true
        // The feed never keeps the screen awake or takes over other audio
        // for a muted clip nobody asked for.
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let saving = path.isConstrained || path.isExpensive
            Task { @MainActor [weak self] in self?.update { $0.isSavingData = saving } }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }

    // MARK: What the feed tells it

    /// The clips on the page, in drawing order. Called when the page changes.
    func setClips(_ next: [Clip]) {
        guard next != clips else { return }
        clips = next
        let known = Set(next.map(\.postID))
        visibility = visibility.filter { known.contains($0.key) }
        failedPostIDs.formIntersection(known)
        replan()
    }

    /// How much of a card is on screen, from 0 to 1.
    func setVisibility(_ fraction: Double, postID: Int) {
        guard visibility[postID] != fraction else { return }
        visibility[postID] = fraction
        if fraction < FeedPlaybackPolicy.playableFraction, startedByReader == postID {
            startedByReader = nil
            pausedByReader = false
        }
        replan()
    }

    /// The reader's and the device's settings.
    func update(_ change: (inout FeedPlaybackSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        replan()
    }

    /// Whether the feed is in front with nothing over it.
    func setFeedActive(_ active: Bool) {
        guard active != isFeedActive else { return }
        isFeedActive = active
        replan()
    }

    /// Where the feed has scrolled to. Speed is worked out here, so the feed
    /// only has to say where it is.
    func scrolled(toOffset y: CGFloat) {
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastOffset = (y, now) }
        guard let last = lastOffset, now > last.at else { return }
        let speed = Double(y - last.y) / (now - last.at)
        let rapid = FeedPlaybackPolicy.isRapid(pointsPerSecond: speed)
        if rapid != isScrollingRapidly {
            isScrollingRapidly = rapid
            replan()
        }
        // Scroll events simply stop when scrolling does, so "settled" is
        // the absence of one for a moment.
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled, self.isScrollingRapidly else { return }
            self.isScrollingRapidly = false
            self.replan()
        }
    }

    /// The reader tapped a card's clip: play it, or pause it if it is the
    /// one playing.
    func toggle(postID: Int) {
        if activePostID == postID {
            pausedByReader.toggle()
            pausedByReader ? player.pause() : player.play()
            return
        }
        startedByReader = postID
        pausedByReader = false
        failedPostIDs.remove(postID)
        replan()
    }

    var isPausedByReader: Bool { pausedByReader }

    /// Stops everything and lets go of what was loaded: the feed is leaving.
    func stop() {
        settleTask?.cancel()
        startedByReader = nil
        pausedByReader = false
        activate(nil)
        prepared = nil
    }

    // MARK: Making the player match the plan

    private func replan() {
        let plan = FeedPlaybackPolicy.plan(
            clips: clips.map { FeedClip(postID: $0.postID, visibleFraction: visibility[$0.postID] ?? 0) },
            current: activePostID,
            startedByReader: startedByReader,
            settings: settings,
            isScrollingRapidly: isScrollingRapidly,
            isFeedActive: isFeedActive
        )
        if plan.active != activePostID { activate(plan.active) }
        prepare(plan.prepared)
    }

    private func item(for clip: Clip) -> AVPlayerItem {
        let item = AVPlayerItem(url: clip.url)
        // The limits the app already played clips under.
        item.preferredPeakBitRate = 1_300_000
        item.preferredMaximumResolution = CGSize(width: 854, height: 854)
        // Enough to start promptly, not a whole clip nobody may watch.
        item.preferredForwardBufferDuration = 2
        return item
    }

    private func prepare(_ postID: Int?) {
        guard let postID, let clip = clips.first(where: { $0.postID == postID }),
              !failedPostIDs.contains(postID) else {
            // Dropping the item cancels its loading.
            prepared = nil
            return
        }
        guard prepared?.postID != postID else { return }
        prepared = (postID, item(for: clip))
    }

    private func activate(_ postID: Int?) {
        if let previous = activePostID {
            report(previous, .notPlaying(Self.milliseconds(player.currentTime())))
        }
        observations.forEach { $0.invalidate() }
        observations = []
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
        isBuffering = false
        activePostID = postID

        guard let postID, let clip = clips.first(where: { $0.postID == postID }) else {
            player.replaceCurrentItem(with: nil)
            return
        }
        let next: AVPlayerItem
        if let ready = prepared, ready.postID == postID {
            next = ready.item
            prepared = nil
        } else {
            next = item(for: clip)
        }
        player.replaceCurrentItem(with: next)
        player.isMuted = isMuted

        observations.append(next.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                guard let self, self.activePostID == postID else { return }
                self.failedPostIDs.insert(postID)
                self.report(postID, .failed)
                if self.startedByReader == postID { self.startedByReader = nil }
                self.replan()
            }
        })
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            let position = Self.milliseconds(player.currentTime())
            Task { @MainActor [weak self] in
                guard let self, self.activePostID == postID else { return }
                self.isBuffering = status == .waitingToPlayAtSpecifiedRate
                self.report(postID, status == .playing ? .playing(position) : .notPlaying(position))
            }
        })
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            let position = Self.milliseconds(time)
            Task { @MainActor [weak self] in
                guard let self, self.activePostID == postID else { return }
                self.report(postID, .progress(position))
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: next, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.activePostID == postID else { return }
                self.report(postID, .ended)
                // A short clip loops, as feeds do. The measurement counts
                // the first pass as coverage and the rest as rewatch.
                await self.player.seek(to: .zero)
                guard self.activePostID == postID, !self.pausedByReader else { return }
                self.player.play()
            }
        }
        player.play()
    }

    private nonisolated static func milliseconds(_ time: CMTime) -> Double {
        guard time.isValid, time.seconds.isFinite else { return 0 }
        return max(0, time.seconds * 1000)
    }
}
