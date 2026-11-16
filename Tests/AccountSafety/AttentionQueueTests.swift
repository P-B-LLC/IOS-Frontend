import Foundation
import XCTest
@testable import AccountSafety

/// Summaries waiting to be sent: bounded, and safe to send twice.
final class AttentionQueueTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func summary(_ sequence: Int, age: TimeInterval = 0) -> AttentionSummary {
        AttentionSummary(
            postID: sequence, surface: "for_you", sequence: sequence,
            observedAt: now.addingTimeInterval(-age), dwellMilliseconds: 2000,
            activeDwellMilliseconds: 2000, playbackMilliseconds: nil, coverageMilliseconds: nil,
            rewatchMilliseconds: nil, completed: false, playbackFailed: false,
            attachmentOpened: false, attachmentReadMilliseconds: 0
        )
    }

    private func filled(_ count: Int) -> AttentionQueue {
        var queue = AttentionQueue()
        for sequence in 1...count { queue.add(summary(sequence), now: now) }
        return queue
    }

    func testABatchIsAtMostFiftyOldestFirst() {
        var queue = filled(120)
        XCTAssertTrue(queue.hasFullBatch)
        let batch = queue.nextBatch(now: now)
        XCTAssertEqual(batch?.summaries.map(\.sequence), Array(1...50))
        XCTAssertEqual(batch?.sessionID, queue.sessionID)
        XCTAssertEqual(queue.count, 120, "sealed, not gone, until acknowledged")
    }

    func testAnInterruptedFlushSendsTheSameBatchWithTheSameIDAgain() {
        var queue = filled(60)
        let first = queue.nextBatch(now: now)
        // The request was made and the answer never came. More arrives.
        queue.add(summary(61), now: now)
        let retry = queue.nextBatch(now: now)
        XCTAssertEqual(retry, first, "same id, same contents: the server's receipt can recognise it")
        XCTAssertEqual(retry?.summaries.count, 50, "nothing was appended to a sealed batch")
    }

    func testAcknowledgingMovesOnToTheNextBatch() {
        var queue = filled(60)
        let first = queue.nextBatch(now: now)!
        queue.acknowledge(first.id)
        let second = queue.nextBatch(now: now)!
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(second.summaries.map(\.sequence), Array(51...60))
        queue.acknowledge(second.id)
        XCTAssertNil(queue.nextBatch(now: now))
        XCTAssertTrue(queue.isEmpty)
    }

    func testARefusedBatchIsDroppedRatherThanBlockingTheRest() {
        var queue = filled(60)
        let refused = queue.nextBatch(now: now)!
        queue.discard(refused.id)
        XCTAssertEqual(queue.nextBatch(now: now)?.summaries.first?.sequence, 51)
    }

    func testTheQueueHoldsTwoHundredAndDropsTheOldest() {
        var queue = filled(260)
        XCTAssertEqual(queue.count, AttentionQueue.capacity)
        XCTAssertEqual(queue.nextBatch(now: now)?.summaries.first?.sequence, 61)
    }

    func testOverCapacityAnUnacknowledgedBatchGoesBeforeAnythingNewer() {
        var queue = filled(50)
        let stuck = queue.nextBatch(now: now)!
        for sequence in 51...250 { queue.add(summary(sequence), now: now) }
        XCTAssertEqual(queue.count, AttentionQueue.capacity)
        XCTAssertNotEqual(queue.nextBatch(now: now)?.id, stuck.id)
        XCTAssertEqual(queue.nextBatch(now: now)?.summaries.first?.sequence, 51)
    }

    func testNothingOlderThanADayIsSent() {
        var queue = AttentionQueue()
        queue.add(summary(1, age: 25 * 60 * 60), now: now)
        queue.add(summary(2, age: 23 * 60 * 60), now: now)
        XCTAssertEqual(queue.nextBatch(now: now)?.summaries.map(\.sequence), [2])
        // A sealed batch ages out too, while the phone was offline.
        XCTAssertNil(queue.nextBatch(now: now.addingTimeInterval(2 * 60 * 60)))
        XCTAssertTrue(queue.isEmpty)
    }

    func testSwitchingAccountsEmptiesTheQueueAndTakesANewSession() {
        var queue = filled(60)
        _ = queue.nextBatch(now: now)
        let before = queue.sessionID
        queue.reset()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.nextBatch(now: now))
        XCTAssertNotEqual(queue.sessionID, before)
    }
}
