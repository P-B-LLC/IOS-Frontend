//
//  FeedPlaybackPolicy.swift
//  IOS Frontend
//
//  Which clip in the feed plays, which one is got ready, and when neither.
//

import Foundation

/// What the reader and the device allow a feed to do without being asked.
nonisolated struct FeedPlaybackSettings: Equatable, Sendable {
    /// The reader's own choice in settings. On unless they turned it off.
    var autoplayPreferred = true
    /// Reduce Motion: nothing starts moving that the reader did not start.
    var reduceMotion = false
    /// Low Data Mode, or a connection the system marks expensive or
    /// constrained: no bytes are spent on a clip nobody asked for.
    var isSavingData = false

    /// Whether a clip may start by itself as its card settles on screen.
    var allowsAutoplay: Bool { autoplayPreferred && !reduceMotion && !isSavingData }
    /// Whether the clip after the active one may be got ready in advance.
    /// Never while saving data, and pointless when nothing will autoplay.
    var allowsPreparing: Bool { allowsAutoplay }
}

/// One clip the feed could play, in the order the feed draws them.
nonisolated struct FeedClip: Equatable, Sendable {
    var postID: Int
    /// How much of the card is on screen, from 0 to 1.
    var visibleFraction: Double
}

/// What the feed should be doing with its one player right now.
nonisolated struct FeedPlaybackPlan: Equatable, Sendable {
    /// The clip that plays. At most one, ever.
    var active: Int?
    /// The clip to get ready behind it. At most one, and never the active
    /// one.
    var prepared: Int?
}

/// Decides the plan. Pure: the same cards, settings and scrolling state give
/// the same answer, so every rule below can be run on a Mac with no player.
///
/// The rules, each from the plan for this milestone:
///
/// - **One active player.** The card most on screen wins, provided it is at
///   least sixty percent visible -- the same line the measurement draws, so
///   a clip that is playing is always one that is being counted. A tie goes
///   to the card nearer the top, and whoever is already playing keeps
///   playing through a tie, so two cards sharing the screen do not swap
///   back and forth.
/// - **A clip the reader started keeps playing** while it is at all eligible,
///   whatever else is more visible. They chose it.
/// - **Prepare at most the next clip**, the first one below the active card,
///   and only when autoplay is allowed: preparing spends data and memory on
///   a guess.
/// - **Nothing is prepared during rapid scrolling**, and nothing new starts.
///   Cards are passing too fast to watch; a player spun up for each would be
///   torn down unwatched. What is already playing carries on until its card
///   leaves.
/// - **Covered or backgrounded, nothing plays.**
nonisolated enum FeedPlaybackPolicy {
    /// The least of a card that must be visible for its clip to play. The
    /// measurement's own line.
    static let playableFraction = AttentionMeter.visibleFraction
    /// Faster than this, in points a second, is scrolling past rather than
    /// scrolling to.
    static let rapidScrollSpeed: Double = 1500

    static func plan(
        clips: [FeedClip],
        current: Int?,
        startedByReader: Int? = nil,
        settings: FeedPlaybackSettings,
        isScrollingRapidly: Bool,
        isFeedActive: Bool
    ) -> FeedPlaybackPlan {
        guard isFeedActive else { return FeedPlaybackPlan(active: nil, prepared: nil) }
        let eligible = clips.filter { $0.visibleFraction >= playableFraction }

        var active: Int?
        if let chosen = startedByReader, eligible.contains(where: { $0.postID == chosen }) {
            active = chosen
        } else if settings.allowsAutoplay {
            let best = eligible.map(\.visibleFraction).max()
            let leaders = eligible.filter { $0.visibleFraction == best }
            if let current, leaders.contains(where: { $0.postID == current }) {
                active = current
            } else if isScrollingRapidly {
                // Nothing new starts mid-fling; what was playing may finish
                // its time on screen.
                active = eligible.contains(where: { $0.postID == current }) ? current : nil
            } else {
                active = leaders.first?.postID
            }
        }

        var prepared: Int?
        if settings.allowsPreparing, !isScrollingRapidly, let active,
           let index = clips.firstIndex(where: { $0.postID == active }),
           clips.indices.contains(index + 1) {
            prepared = clips[index + 1].postID
        }
        return FeedPlaybackPlan(active: active, prepared: prepared)
    }

    /// Whether a scroll is too fast to be worth starting anything for.
    static func isRapid(pointsPerSecond: Double) -> Bool {
        abs(pointsPerSecond) > rapidScrollSpeed
    }
}
