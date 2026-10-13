//
//  ImpressionTracker.swift
//  IOS Frontend
//
//  What was on screen, for how long, gathered into batches for the server.
//

import Foundation

/// One post having been on screen, as the server wants to hear about it.
nonisolated struct ImpressionEvent: Equatable, Sendable {
    var postID: Int
    var dwellMilliseconds: Int
    /// How far into the post's clip this viewing got, when it has one and it
    /// played.
    var watchMilliseconds: Int?
    var completed: Bool
}

/// The arithmetic of impressions, kept apart from SwiftUI and the network so
/// it can be reasoned about -- and run -- on its own. `SocialStore` owns one,
/// tells it as cards come and go, and sends the batches it hands back.
///
/// The rules are the web client's (`src/lib/impressions.ts`), so a reader is
/// measured the same way on either:
///
/// - a post is on screen from when most of it is visible until it is not; a
///   second "shown" while it still is, is the same viewing;
/// - every figure is capped at what the server accepts, because one wild
///   number would get the whole batch refused;
/// - a clip's furthest point and whether it finished travel with the viewing
///   they happened in -- or, when the clip reports after its card has already
///   gone, are added to that viewing before it is sent.
///
/// Nothing is retried. These are signals for ranking, and resending an old
/// batch later would only describe a session that is over.
nonisolated struct ImpressionTracker: Sendable {
    /// The server's ceilings. Exceeding any of them refuses the whole batch.
    static let maxBatch = 50
    static let maxDwellMilliseconds = 10 * 60 * 1000
    static let maxWatchMilliseconds = 60 * 60 * 1000

    private struct Watching: Sendable {
        var milliseconds: Int
        var completed: Bool
    }

    private var onScreen: [Int: Date] = [:]
    private var watching: [Int: Watching] = [:]
    /// Finished viewings waiting to be sent, oldest first.
    private(set) var pending: [ImpressionEvent] = []

    /// Whether there is anything to send now.
    var hasPending: Bool { !pending.isEmpty }

    /// Whether a post is being counted as on screen.
    func isOnScreen(_ postID: Int) -> Bool {
        onScreen[postID] != nil
    }

    /// The post came into view.
    mutating func shown(_ postID: Int, at now: Date = Date()) {
        if onScreen[postID] == nil { onScreen[postID] = now }
    }

    /// The post left view: that is one viewing, and it is queued.
    mutating func hidden(_ postID: Int, at now: Date = Date()) {
        guard let since = onScreen.removeValue(forKey: postID) else { return }
        let clip = watching.removeValue(forKey: postID)
        let dwell = Int((now.timeIntervalSince(since) * 1000).rounded())
        pending.append(ImpressionEvent(
            postID: postID,
            dwellMilliseconds: min(max(dwell, 0), Self.maxDwellMilliseconds),
            watchMilliseconds: clip.map { min(max($0.milliseconds, 0), Self.maxWatchMilliseconds) },
            completed: clip?.completed ?? false
        ))
    }

    /// How far into a post's clip playback has got, and whether it reached
    /// the end. Only ever moves forward within a viewing.
    mutating func watched(_ postID: Int, milliseconds: Int, completed: Bool = false) {
        let position = min(max(milliseconds, 0), Self.maxWatchMilliseconds)
        if onScreen[postID] != nil {
            let current = watching[postID] ?? Watching(milliseconds: 0, completed: false)
            watching[postID] = Watching(
                milliseconds: max(current.milliseconds, position),
                completed: current.completed || completed
            )
        } else if let index = pending.lastIndex(where: { $0.postID == postID }) {
            // The clip stops a moment after its card counts as gone, and the
            // last of its progress belongs to the viewing that just closed.
            pending[index].watchMilliseconds = max(pending[index].watchMilliseconds ?? 0, position)
            pending[index].completed = pending[index].completed || completed
        }
        // Otherwise it was watched somewhere this tracker is not counting --
        // a post's own page -- and there is no viewing to attach it to.
    }

    /// Closes every open viewing: the screen is going away.
    mutating func closeAll(at now: Date = Date()) {
        for postID in Array(onScreen.keys).sorted() {
            hidden(postID, at: now)
        }
    }

    /// Up to one batch of what is queued, taken off the queue.
    mutating func nextBatch() -> [ImpressionEvent] {
        let batch = Array(pending.prefix(Self.maxBatch))
        pending.removeFirst(batch.count)
        return batch
    }

    /// Forgets everything: another account is signing in.
    mutating func reset() {
        onScreen = [:]
        watching = [:]
        pending = []
    }
}
