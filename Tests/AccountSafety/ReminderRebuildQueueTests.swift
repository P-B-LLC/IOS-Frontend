import XCTest
@testable import AccountSafety

@MainActor
final class ReminderRebuildQueueTests: XCTestCase {
    func testCancellingCallerDoesNotInterruptScheduleAfterClear() async {
        let queue = ReminderRebuildQueue()
        let started = expectation(description: "Schedule cleared")
        var resume: CheckedContinuation<Void, Never>?
        var scheduled: [Int] = []
        let caller = Task {
            await queue.enqueue {
                scheduled.removeAll()
                await withCheckedContinuation { continuation in
                    resume = continuation
                    started.fulfill()
                }
                if !Task.isCancelled { scheduled = [15, 5, 1] }
            }.value
        }
        await fulfillment(of: [started], timeout: 2)
        caller.cancel()
        resume?.resume()
        await caller.value
        XCTAssertEqual(scheduled, [15, 5, 1])
    }

    func testNewerRequestsCoalesceWithoutOverlappingWrites() async {
        let queue = ReminderRebuildQueue()
        let started = expectation(description: "First write suspended")
        var resume: CheckedContinuation<Void, Never>?
        var writes: [Int] = []
        let worker = queue.enqueue {
            await withCheckedContinuation { continuation in
                resume = continuation
                started.fulfill()
            }
            writes.append(1)
        }
        await fulfillment(of: [started], timeout: 2)
        _ = queue.enqueue { writes.append(2) }
        _ = queue.enqueue { writes.append(3) }
        resume?.resume()
        await worker.value
        XCTAssertEqual(writes, [1, 3])
    }

    func testAccountResetDiscardsQueuedOldAccountSnapshot() async {
        let queue = ReminderRebuildQueue()
        let started = expectation(description: "Active write")
        var resume: CheckedContinuation<Void, Never>?
        var pendingRan = false
        let worker = queue.enqueue {
            await withCheckedContinuation { continuation in
                resume = continuation
                started.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 2)
        _ = queue.enqueue { pendingRan = true }
        queue.discardPending()
        resume?.resume()
        await worker.value
        XCTAssertFalse(pendingRan)
    }
}
