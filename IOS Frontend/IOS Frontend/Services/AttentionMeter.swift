//
//  AttentionMeter.swift
//  IOS Frontend
//
//  What a reader actually gave a post, measured on the device.
//

import Foundation

/// One exposure of one post, summed up when it ends. This is the whole of
/// what leaves the device about it: no timeline, no taps, one row.
///
/// Every duration is in milliseconds. A playback figure is nil when the post
/// has no clip, which says "does not apply" and is not the same as zero.
nonisolated struct AttentionSummary: Codable, Equatable, Sendable {
    var postID: Int
    var surface: String
    /// This exposure's number within the session, counting up from one.
    var sequence: Int
    /// When the exposure ended, by the wall clock.
    var observedAt: Date
    /// From becoming eligible to leaving, whatever happened in between.
    var dwellMilliseconds: Int
    /// The part of that with the app in front and nothing over the card.
    var activeDwellMilliseconds: Int
    /// Time the player was actually playing while the post was eligible.
    var playbackMilliseconds: Int?
    /// How much of the clip was played, each part counted once.
    var coverageMilliseconds: Int?
    /// Time spent on parts already played in this exposure.
    var rewatchMilliseconds: Int?
    /// The clip reached its natural end with nine tenths of it covered.
    var completed: Bool
    var playbackFailed: Bool
    var attachmentOpened: Bool
    var attachmentReadMilliseconds: Int
}

/// The measuring itself: told what happens to cards and players, it keeps a
/// clock per post and hands back a summary when an exposure ends.
///
/// Kept apart from SwiftUI, AVFoundation and the network so that every rule
/// here can be run, with a clock the test holds, on a Mac with no simulator.
///
/// **Time** is a monotonic count of seconds that the caller passes in
/// (`ProcessInfo.systemUptime` in the app). The wall clock is used for one
/// thing, stamping when an exposure ended; a wall clock that is set back
/// mid-scroll must not produce a negative dwell.
///
/// **Eligible** means the post is at least sixty percent visible, the app is
/// active, and no sheet or other screen is over the feed. A post is exposed
/// while it is visible; its active clock and its playback clock run only
/// while it is eligible. Covering the feed suspends them without ending the
/// exposure, so opening the recipe and coming back is one exposure with a
/// gap in it, not two.
///
/// **Coverage** is the union of the stretches of the clip that were played.
/// A stretch is extended only by a progress report that follows the last one
/// at a believable speed; anything else -- a seek, in either direction -- starts
/// a new stretch from where it landed. Seeking to the end therefore covers
/// nothing, which is the point: the old tracker reported the furthest
/// position, and a seek reaches that without anything being watched.
nonisolated struct AttentionMeter: Sendable {
    /// Shorter than this is a flick past, and is not reported.
    static let minimumExposure: TimeInterval = 0.25
    /// The fraction of a card that must be visible for it to count.
    static let visibleFraction = 0.6
    /// The share of a clip that must be covered for it to be watched through.
    static let completionCoverage = 0.9
    /// The server's ceilings, so one runaway figure cannot refuse a batch.
    static let maxMilliseconds = 10 * 60 * 1000
    /// The fastest the player plays, and the room a report is given either
    /// side of the wall clock before it is taken for a seek.
    static let maxRate = 2.0
    static let slackMilliseconds = 400.0

    private struct Playback: Sendable {
        var durationMilliseconds: Int
        /// When the player last started actually playing, or nil while it is
        /// paused, buffering, ended -- or suspended by the card's ineligibility.
        var playingSince: TimeInterval?
        /// Whether the player itself says it is playing, eligible or not.
        var wantsToPlay = false
        var playedSeconds: TimeInterval = 0
        /// The media position of the last report, and when it was made.
        var lastPosition: Double?
        var lastReportAt: TimeInterval?
        /// Played stretches of the clip, in media milliseconds, kept sorted
        /// and merged.
        var covered: [ClosedRange<Double>] = []
        /// Media milliseconds moved through at playing speed, in all.
        var traversed: Double = 0
        var endedNaturally = false
        var failed = false

        var coverage: Double {
            covered.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        }
    }

    private struct Exposure: Sendable {
        var surface: String
        var since: TimeInterval
        /// Running total of active time, and when the current stretch began.
        var activeSeconds: TimeInterval = 0
        var activeSince: TimeInterval?
        var playback: Playback?
        var attachmentOpened = false
        var attachmentSeconds: TimeInterval = 0
        var attachmentSince: TimeInterval?
    }

    private var exposures: [Int: Exposure] = [:]
    private var appIsActive = true
    private var coveredBy = 0
    private(set) var sequence = 0

    /// Whether a post is being counted as exposed.
    func isExposed(_ postID: Int) -> Bool { exposures[postID] != nil }

    private var isUncovered: Bool { appIsActive && coveredBy == 0 }

    // MARK: Cards

    /// The card is at least sixty percent visible. A second report while it
    /// still is, is the same exposure.
    mutating func shown(_ postID: Int, surface: String, at now: TimeInterval) {
        guard exposures[postID] == nil else { return }
        var exposure = Exposure(surface: surface, since: now)
        if isUncovered { exposure.activeSince = now }
        exposures[postID] = exposure
    }

    /// The card is no longer visible enough: the exposure is over.
    mutating func hidden(_ postID: Int, at now: TimeInterval, wallClock: Date = Date()) -> AttentionSummary? {
        guard var exposure = exposures.removeValue(forKey: postID) else { return nil }
        suspend(&exposure, at: now)
        if let since = exposure.attachmentSince {
            exposure.attachmentSeconds += max(0, now - since)
        }
        let dwell = max(0, now - exposure.since)
        guard dwell >= Self.minimumExposure else { return nil }
        sequence += 1
        let playback = exposure.playback
        let coverage = playback.map { min($0.coverage, Double($0.durationMilliseconds)) }
        return AttentionSummary(
            postID: postID,
            surface: exposure.surface,
            sequence: sequence,
            observedAt: wallClock,
            dwellMilliseconds: Self.milliseconds(dwell),
            activeDwellMilliseconds: Self.milliseconds(min(exposure.activeSeconds, dwell)),
            playbackMilliseconds: playback.map { Self.milliseconds(min($0.playedSeconds, exposure.activeSeconds)) },
            coverageMilliseconds: coverage.map { Int($0.rounded()) },
            rewatchMilliseconds: playback.map { Int(max(0, $0.traversed - $0.coverage).rounded()) },
            completed: playback.map {
                $0.endedNaturally && $0.durationMilliseconds > 0
                    && $0.coverage >= Self.completionCoverage * Double($0.durationMilliseconds)
            } ?? false,
            playbackFailed: playback?.failed ?? false,
            attachmentOpened: exposure.attachmentOpened,
            attachmentReadMilliseconds: Self.milliseconds(exposure.attachmentSeconds)
        )
    }

    /// Ends every exposure: the feed is leaving the screen.
    mutating func hideAll(at now: TimeInterval, wallClock: Date = Date()) -> [AttentionSummary] {
        exposures.keys.sorted().compactMap { hidden($0, at: now, wallClock: wallClock) }
    }

    // MARK: What stops the clocks

    /// The app came to the front or left it.
    mutating func appBecameActive(_ active: Bool, at now: TimeInterval) {
        guard active != appIsActive else { return }
        let was = isUncovered
        appIsActive = active
        eligibilityChanged(from: was, at: now)
    }

    /// A sheet or another screen went over the feed, or came off it. Counted
    /// rather than flagged, because sheets stack.
    mutating func feedCovered(_ covered: Bool, at now: TimeInterval) {
        let was = isUncovered
        coveredBy = max(0, coveredBy + (covered ? 1 : -1))
        eligibilityChanged(from: was, at: now)
    }

    private mutating func eligibilityChanged(from was: Bool, at now: TimeInterval) {
        guard was != isUncovered else { return }
        for postID in exposures.keys {
            guard var exposure = exposures[postID] else { continue }
            if isUncovered {
                exposure.activeSince = now
                if exposure.playback?.wantsToPlay == true {
                    exposure.playback?.playingSince = now
                    // Whatever the player did meanwhile was not watched: the
                    // next report starts a new stretch.
                    exposure.playback?.lastPosition = nil
                }
            } else {
                suspend(&exposure, at: now)
            }
            exposures[postID] = exposure
        }
    }

    /// Stops an exposure's active and playback clocks, banking what ran.
    private func suspend(_ exposure: inout Exposure, at now: TimeInterval) {
        if let since = exposure.activeSince {
            exposure.activeSeconds += max(0, now - since)
            exposure.activeSince = nil
        }
        if let since = exposure.playback?.playingSince {
            exposure.playback?.playedSeconds += max(0, now - since)
            exposure.playback?.playingSince = nil
        }
    }

    // MARK: The attachment

    /// The reader opened the post's workout or recipe. The sheet covers the
    /// feed, so the caller reports that too; this is what makes the time in
    /// it count as reading rather than as nothing.
    mutating func attachmentOpened(_ postID: Int, at now: TimeInterval) {
        guard exposures[postID] != nil, exposures[postID]?.attachmentSince == nil else { return }
        exposures[postID]?.attachmentOpened = true
        exposures[postID]?.attachmentSince = now
    }

    mutating func attachmentClosed(_ postID: Int, at now: TimeInterval) {
        guard let since = exposures[postID]?.attachmentSince else { return }
        exposures[postID]?.attachmentSeconds += max(0, now - since)
        exposures[postID]?.attachmentSince = nil
    }

    // MARK: The player

    /// The post has a clip of this length. Without this an exposure reports
    /// no playback at all, which is right for a photo.
    mutating func hasClip(_ postID: Int, durationMilliseconds: Int) {
        guard exposures[postID] != nil, exposures[postID]?.playback == nil else { return }
        exposures[postID]?.playback = Playback(durationMilliseconds: max(0, durationMilliseconds))
    }

    /// The player started or stopped actually playing. Buffering and pausing
    /// are both "not playing": only time with frames moving is watching.
    mutating func playing(_ isPlaying: Bool, postID: Int, positionMilliseconds: Double, at now: TimeInterval) {
        guard var exposure = exposures[postID], var playback = exposure.playback else { return }
        if isPlaying {
            playback.wantsToPlay = true
            if playback.playingSince == nil, isUncovered { playback.playingSince = now }
            playback.lastPosition = positionMilliseconds
            playback.lastReportAt = now
        } else {
            record(&playback, position: positionMilliseconds, at: now)
            playback.wantsToPlay = false
            if let since = playback.playingSince {
                playback.playedSeconds += max(0, now - since)
                playback.playingSince = nil
            }
            playback.lastPosition = nil
        }
        exposure.playback = playback
        exposures[postID] = exposure
    }

    /// Where playback has got to, reported as it goes.
    mutating func progress(_ postID: Int, positionMilliseconds: Double, at now: TimeInterval) {
        guard var playback = exposures[postID]?.playback else { return }
        record(&playback, position: positionMilliseconds, at: now)
        exposures[postID]?.playback = playback
    }

    /// The reader moved the playhead. Nothing between here and there was
    /// played.
    mutating func seeked(_ postID: Int, toMilliseconds position: Double, at now: TimeInterval) {
        guard exposures[postID]?.playback != nil else { return }
        exposures[postID]?.playback?.lastPosition = position
        exposures[postID]?.playback?.lastReportAt = now
    }

    /// The clip played to its end by itself.
    mutating func ended(_ postID: Int, at now: TimeInterval) {
        guard let duration = exposures[postID]?.playback?.durationMilliseconds else { return }
        playing(false, postID: postID, positionMilliseconds: Double(duration), at: now)
        exposures[postID]?.playback?.endedNaturally = true
    }

    /// The clip could not start, or stalled until the reader gave up.
    mutating func failed(_ postID: Int, at now: TimeInterval) {
        guard exposures[postID]?.playback != nil else { return }
        playing(false, postID: postID, positionMilliseconds: exposures[postID]?.playback?.lastPosition ?? 0, at: now)
        exposures[postID]?.playback?.failed = true
    }

    /// Extends the played stretch to `position` if playback can have got
    /// there from the last report by playing; otherwise treats it as a jump.
    private func record(_ playback: inout Playback, position: Double, at now: TimeInterval) {
        defer {
            playback.lastPosition = position
            playback.lastReportAt = now
        }
        // Only while frames were moving in front of the reader.
        guard playback.playingSince != nil,
              let last = playback.lastPosition, let lastAt = playback.lastReportAt else { return }
        let moved = position - last
        let allowed = max(0, now - lastAt) * 1000 * Self.maxRate + Self.slackMilliseconds
        guard moved > 0, moved <= allowed else { return }
        let limit = Double(playback.durationMilliseconds)
        let lower = min(max(last, 0), limit), upper = min(max(position, 0), limit)
        guard upper > lower else { return }
        playback.traversed += upper - lower
        playback.covered = Self.union(playback.covered, with: lower...upper)
    }

    static func union(_ ranges: [ClosedRange<Double>], with added: ClosedRange<Double>) -> [ClosedRange<Double>] {
        var merged: [ClosedRange<Double>] = []
        var current = added
        var placed = false
        for range in ranges {
            if range.upperBound < current.lowerBound {
                merged.append(range)
            } else if current.upperBound < range.lowerBound {
                if !placed { merged.append(current); placed = true }
                merged.append(range)
            } else {
                current = min(range.lowerBound, current.lowerBound)...max(range.upperBound, current.upperBound)
            }
        }
        if !placed { merged.append(current) }
        return merged
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int {
        min(max(Int((seconds * 1000).rounded()), 0), maxMilliseconds)
    }

    /// Forgets every open exposure and starts counting again: another
    /// account is signing in, and nothing of this one's may be reported as
    /// theirs.
    mutating func reset() {
        exposures = [:]
        coveredBy = 0
        sequence = 0
    }
}
