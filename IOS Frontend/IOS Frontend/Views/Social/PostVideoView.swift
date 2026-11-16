import AVKit
import Foundation
import PhotosUI
import SwiftUI

/// Creating the player is a deliberate action, never a side effect of feed rendering.
struct PostVideoView: View {
    let postID: Int
    let video: PostVideoMedia
    let canReplace: Bool
    @Environment(SocialStore.self) private var social
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var loading = false
    @State private var failure: String?
    @State private var refreshed: PostVideoMedia?
    @State private var observation: NSKeyValueObservation?
    @State private var playbackObservation: NSKeyValueObservation?
    /// How far playback has got, reported to For You while it plays, so a
    /// clip watched to the end reads differently from one abandoned at once.
    @State private var progressObserver: Any?
    @State private var endObserver: (any NSObjectProtocol)?
    @State private var didRecordStart = false
    @State private var requestGeneration = UUID()
    @State private var replacement: PhotosPickerItem?

    private var current: PostVideoMedia { refreshed ?? video }

    var body: some View {
        VStack(spacing: 8) {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 240)
                    .overlay { if loading { ProgressView().tint(.white) } }
            } else if current.canPlay {
                Button { play() } label: {
                    ZStack {
                        Color.secondary.opacity(0.12)
                        AsyncImage(url: current.thumbnailURL) { image in
                            image.resizable().scaledToFit()
                        } placeholder: { Color.clear }
                        Image(systemName: "play.circle.fill").font(.system(size: 48))
                            .foregroundStyle(.white).shadow(radius: 3)
                    }.frame(height: 220).clipped()
                }.buttonStyle(.plain).accessibilityLabel("Play video")
            } else {
                Label(statusText, systemImage: current.failed ? "exclamationmark.triangle" : "video")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Refresh status") { refresh() }.disabled(loading)
                if current.failed && canReplace {
                    PhotosPicker(selection: $replacement, matching: .videos, preferredItemEncoding: .current) {
                        Label("Choose another video", systemImage: "video.badge.plus")
                    }.disabled(loading || social.isPosting)
                }
            }
            if loading && player == nil { ProgressView("Loading video…") }
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.secondary)
                Button("Try again") { stop(); play() }.disabled(loading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onDisappear { requestGeneration = UUID(); stop() }
        .task(id: replacement) {
            guard let replacement else { return }
            loading = true
            var draft: PostVideoDraft?
            defer { draft?.discard(); loading = false; self.replacement = nil }
            do {
                draft = try await replacement.loadTransferable(type: PostVideoDraft.self)
                guard let draft else { throw VideoBetaLimits.ValidationError.format }
                try await draft.validate()
                try Task.checkCancellation()
                if await social.retryVideo(postID: postID, draft: draft) {
                    refreshed = social.lastPosted?.video
                    failure = nil
                } else { failure = String(localized: "Could not attach this video. Try again.", bundle: .app, locale: .app) }
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
        }
        .task(id: current.processingState) {
            // The author's own clip, still being encoded: check back until it
            // is ready, rather than leaving them to tap Refresh to find out.
            // Six minutes covers a full-length clip on the beta's one worker.
            guard canReplace, Self.isEncoding(current.processingState) else { return }
            for _ in 0..<72 {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, player == nil else { return }
                guard let latest = try? await social.refreshVideo(postID: postID) else { continue }
                refreshed = latest
                if !Self.isEncoding(latest.processingState) { return }
            }
        }
        .onChange(of: social.isConnected) { if !social.isConnected { stop() } }
        .onChange(of: scenePhase) { if scenePhase != .active { stop() } }
        .onScrollVisibilityChange(threshold: 0.25) { visible in if !visible { stop() } }
    }

    private static func isEncoding(_ state: String) -> Bool {
        state == "uploading" || state == "processing"
    }

    /// Where the clip has got to, as its author is shown it. Nobody else is
    /// sent a clip that cannot play. Encoding is said before review: a clip
    /// still being encoded is also pending review, and saying it waits for a
    /// moderator would be wrong.
    private var statusText: LocalizedStringKey {
        if current.failed { return "Video processing failed" }
        if Self.isEncoding(current.processingState) { return "Video is being prepared" }
        if current.status == "rejected" { return "Your video was not approved" }
        if current.status != "approved" { return "Waiting for review. Others will see it once it is approved." }
        return "Video is being prepared"
    }

    private func refresh() {
        guard !loading else { return }
        loading = true
        let generation = requestGeneration
        Task {
            do {
                let latest = try await social.refreshVideo(postID: postID)
                guard generation == requestGeneration else { return }
                refreshed = latest
                failure = latest == nil ? String(localized: "This video is no longer available.", bundle: .app, locale: .app) : nil
            } catch {
                guard generation == requestGeneration else { return }
                failure = String(localized: "Could not refresh this video. Please try again.", bundle: .app, locale: .app)
            }
            loading = false
        }
    }

    private func play() {
        guard !loading else { return }
        loading = true
        failure = nil
        let generation = requestGeneration
        Task {
            do {
                guard let latest = try await social.refreshVideo(postID: postID), latest.canPlay,
                      let url = latest.url, url.scheme == "https" else { throw CancellationError() }
                guard generation == requestGeneration, scenePhase == .active else { return }
                refreshed = latest
                let item = AVPlayerItem(url: url)
                item.preferredPeakBitRate = 1_300_000
                item.preferredMaximumResolution = CGSize(width: 854, height: 854)
                let next = AVPlayer(playerItem: item)
                player = next
                didRecordStart = false
                observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
                    let status = item.status
                    Task { @MainActor in
                        guard generation == requestGeneration else { return }
                        if status == .readyToPlay {
                            loading = false
                        }
                        if status == .failed {
                            loading = false
                            failure = String(localized: "This video could not play. Please try again.", bundle: .app, locale: .app)
                            // Said to the measurement too, so a clip that
                            // would not play is never read as one skipped.
                            social.attentionPlayback(postID: postID, .failed)
                            await social.recordVideoPlayback(postID: postID, failed: true)
                        }
                    }
                }
                playbackObservation = next.observe(\.timeControlStatus, options: [.new]) { next, _ in
                    let status = next.timeControlStatus
                    let position = Self.milliseconds(next.currentTime())
                    Task { @MainActor in
                        guard generation == requestGeneration else { return }
                        // Only frames moving is watching: buffering and
                        // pausing both stop the playback clock.
                        social.attentionPlayback(
                            postID: postID,
                            status == .playing ? .playing(position) : .notPlaying(position)
                        )
                        loading = status == .waitingToPlayAtSpecifiedRate
                        if status == .playing && !didRecordStart {
                            didRecordStart = true
                            await social.recordVideoPlayback(postID: postID, failed: false)
                        }
                    }
                }
                // Twice a second. Each report extends the stretch of the clip
                // that was played, and one that could not have been reached
                // by playing -- the reader dragged the playhead -- starts a
                // new stretch instead, so a seek covers nothing.
                progressObserver = next.addPeriodicTimeObserver(
                    forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                    queue: .main
                ) { time in
                    let position = Self.milliseconds(time)
                    Task { @MainActor in
                        guard generation == requestGeneration else { return }
                        social.attentionPlayback(postID: postID, .progress(position))
                    }
                }
                endObserver = NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification,
                    object: item,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        guard generation == requestGeneration else { return }
                        social.attentionPlayback(postID: postID, .ended)
                    }
                }
                next.play()
            } catch {
                guard generation == requestGeneration else { return }
                loading = false
                failure = String(localized: "This video is unavailable. Refresh and try again.", bundle: .app, locale: .app)
            }
        }
    }

    private static func milliseconds(_ time: CMTime) -> Double {
        guard time.isValid, time.seconds.isFinite else { return 0 }
        return max(0, time.seconds * 1000)
    }

    private func stop() {
        requestGeneration = UUID()
        observation?.invalidate(); observation = nil
        playbackObservation?.invalidate(); playbackObservation = nil
        if let player {
            // The last of the progress, which the periodic report can be
            // half a second behind.
            social.attentionPlayback(postID: postID, .notPlaying(Self.milliseconds(player.currentTime())))
            if let progressObserver { player.removeTimeObserver(progressObserver) }
        }
        progressObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        loading = false
    }
}
