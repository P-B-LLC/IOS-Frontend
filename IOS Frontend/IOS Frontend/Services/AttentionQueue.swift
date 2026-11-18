//
//  AttentionQueue.swift
//  IOS Frontend
//
//  Summaries waiting to be sent, in batches that can be sent twice.
//

import Foundation

/// A batch as it goes to the server. Its id is made once and never changes:
/// the server keeps a receipt per id, so sending the same batch again after a
/// lost answer adds nothing. That only holds if a batch, once sealed, is never
/// reopened -- which is why this is a value with no way to append to it.
nonisolated struct AttentionBatch: Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let summaries: [AttentionSummary]
}

/// What has been measured and not yet acknowledged, bounded in both
/// directions: at most 200 summaries, none older than 24 hours.
///
/// The bound matters more than any one summary. These are passive
/// measurements; a phone offline for a week must not come back holding a
/// week of them, and must never spend its storage or the reader's data on
/// catching up. When the queue is full the oldest go first.
///
/// Held in memory only. A batch being sent when the app is killed is lost
/// rather than written to disk, where it would need tying to an account and
/// clearing on sign-out to stay private; losing a few seconds of passive
/// measurement costs less than that would.
nonisolated struct AttentionQueue: Sendable {
    static let maxBatch = 50
    static let capacity = 200
    static let lifetime: TimeInterval = 24 * 60 * 60

    /// Random, and this account's alone: made when the account connects and
    /// thrown away when it leaves. Never an identity -- the server takes who
    /// is reporting from the token.
    private(set) var sessionID = UUID()
    /// Summaries not yet in a batch, oldest first.
    private(set) var waiting: [AttentionSummary] = []
    /// Batches sent, or being sent, and not yet acknowledged, oldest first.
    private(set) var sealed: [AttentionBatch] = []

    var count: Int { waiting.count + sealed.reduce(0) { $0 + $1.summaries.count } }
    var isEmpty: Bool { waiting.isEmpty && sealed.isEmpty }
    /// Whether there is a full batch's worth waiting, so it is worth sending
    /// without waiting for the timer.
    var hasFullBatch: Bool { waiting.count >= Self.maxBatch }

    mutating func add(_ summary: AttentionSummary, now: Date = Date()) {
        waiting.append(summary)
        trim(now: now)
    }

    /// The next batch to send: one already sealed and never acknowledged,
    /// unchanged, before anything new.
    mutating func nextBatch(now: Date = Date(), makeID: () -> UUID = UUID.init) -> AttentionBatch? {
        trim(now: now)
        if let unacknowledged = sealed.first { return unacknowledged }
        guard !waiting.isEmpty else { return nil }
        let batch = AttentionBatch(
            id: makeID(),
            sessionID: sessionID,
            summaries: Array(waiting.prefix(Self.maxBatch))
        )
        waiting.removeFirst(batch.summaries.count)
        sealed.append(batch)
        return batch
    }

    /// The server has it -- recorded now, or recognised as a repeat. Either
    /// way it is done.
    mutating func acknowledge(_ id: UUID) {
        sealed.removeAll { $0.id == id }
    }

    /// The server refused it outright. Sending it again would be refused
    /// again, so it is dropped rather than left to block everything behind
    /// it.
    mutating func discard(_ id: UUID) {
        sealed.removeAll { $0.id == id }
    }

    /// Drops what is too old, then what is over capacity, oldest first.
    private mutating func trim(now: Date) {
        let oldest = now.addingTimeInterval(-Self.lifetime)
        sealed.removeAll { batch in batch.summaries.allSatisfy { $0.observedAt < oldest } }
        waiting.removeAll { $0.observedAt < oldest }
        while count > Self.capacity {
            if !sealed.isEmpty {
                sealed.removeFirst()
            } else {
                waiting.removeFirst(min(waiting.count, count - Self.capacity))
            }
        }
    }

    /// Empties the queue and takes a new session: the account is leaving,
    /// and nothing it measured may be sent as the next one's.
    mutating func reset() {
        waiting = []
        sealed = []
        sessionID = UUID()
    }
}
