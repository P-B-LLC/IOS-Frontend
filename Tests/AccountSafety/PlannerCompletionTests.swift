import Foundation
import XCTest
@testable import AccountSafety

/// Deliberately held responses, not sleeps or real-network timing. The source
/// under test is the same coordinator used by PlannerStore and its controls.
@MainActor
private final class HeldCompletion {
    let started = XCTestExpectation(description: "request started")
    private var continuation: CheckedContinuation<Bool, Error>?
    private(set) var calls = 0

    func send() async throws -> Bool {
        calls += 1
        return try await withCheckedThrowingContinuation {
            continuation = $0
            started.fulfill()
        }
    }

    func resolve(_ result: Result<Bool, Error>) {
        let waiting = continuation
        continuation = nil
        waiting?.resume(with: result)
    }
}

final class PlannerCompletionTests: XCTestCase {
    @MainActor private func wait(_ expectations: [XCTestExpectation]) async {
        let result = await XCTWaiter.fulfillment(of: expectations, timeout: 2)
        XCTAssertEqual(result, .completed, "A held request/callback never completed")
    }

    @MainActor func testRapidOnOffFromMultipleCopiesSendsOneRequestThenAllowsUndo() async {
        let coordinator = PlannerCompletionCoordinator()
        let request = HeldCompletion()
        let saved = XCTestExpectation(description: "confirmed")
        var value = false
        var celebrations = 0
        XCTAssertTrue(coordinator.submit(serverID: 42, current: false, desired: true,
            operation: { try await request.send() }, onSuccess: {
                value = $0; celebrations += 1; saved.fulfill()
            }, onFailure: { _ in XCTFail("Unexpected failure") }))
        // Another copy of task 42 has a different local row ID. Only its server
        // identity participates in the lock; it cannot send the reverse PATCH.
        XCTAssertFalse(coordinator.submit(serverID: 42, current: true, desired: false,
            operation: { XCTFail("Overlapping PATCH"); return false },
            onSuccess: { _ in XCTFail() }, onFailure: { _ in XCTFail() }))
        XCTAssertFalse(value)
        XCTAssertEqual(celebrations, 0)
        XCTAssertTrue(coordinator.isPending(42))
        await wait([request.started])
        XCTAssertEqual(request.calls, 1)
        request.resolve(.success(true))
        await wait([saved])
        XCTAssertTrue(value)
        XCTAssertEqual(celebrations, 1)
        XCTAssertFalse(coordinator.isPending(42))

        let undone = XCTestExpectation(description: "undone")
        XCTAssertTrue(coordinator.submit(serverID: 42, current: value, desired: false,
            operation: { false }, onSuccess: { value = $0; undone.fulfill() },
            onFailure: { _ in XCTFail() }))
        await wait([undone])
        XCTAssertFalse(value)
        XCTAssertEqual(celebrations, 1)
    }

    @MainActor func testReverseResponsesForDifferentTasksDoNotBlockOrRollbackEachOther() async {
        let coordinator = PlannerCompletionCoordinator()
        let first = HeldCompletion(), second = HeldCompletion()
        let firstFailed = XCTestExpectation(description: "first failed")
        let secondSaved = XCTestExpectation(description: "second saved")
        var values = [1: false, 2: false]
        var celebrations: [Int] = []
        coordinator.submit(serverID: 1, current: false, desired: true,
            operation: { try await first.send() }, onSuccess: { _ in XCTFail() },
            onFailure: { _ in firstFailed.fulfill() })
        coordinator.submit(serverID: 2, current: false, desired: true,
            operation: { try await second.send() }, onSuccess: {
                values[2] = $0; celebrations.append(2); secondSaved.fulfill()
            }, onFailure: { _ in XCTFail() })
        await wait([first.started, second.started])
        second.resolve(.success(true))
        await wait([secondSaved])
        XCTAssertTrue(coordinator.isPending(1))
        first.resolve(.failure(URLError(.timedOut)))
        await wait([firstFailed])
        XCTAssertEqual(values, [1: false, 2: true])
        XCTAssertEqual(celebrations, [2])
        XCTAssertFalse(coordinator.isPending(1))
        XCTAssertFalse(coordinator.isPending(2))
    }

    @MainActor func testOldSuccessAndFailureCannotUnlockNewAccountRequest() async {
        for oldResult: Result<Bool, Error> in [.success(true), .failure(URLError(.timedOut))] {
            let coordinator = PlannerCompletionCoordinator()
            let old = HeldCompletion(), fresh = HeldCompletion()
            coordinator.submit(serverID: 7, current: false, desired: true,
                operation: { try await old.send() },
                onSuccess: { _ in XCTFail("Old-account success") },
                onFailure: { _ in XCTFail("Old-account failure") })
            await wait([old.started])
            coordinator.reset()
            let finished = XCTestExpectation(description: "new request finished")
            coordinator.submit(serverID: 7, current: false, desired: true,
                operation: { try await fresh.send() }, onSuccess: { _ in finished.fulfill() },
                onFailure: { _ in XCTFail() })
            await wait([fresh.started])
            old.resolve(oldResult)
            // Enqueue behind the old response on the same actor.
            await Task.yield()
            XCTAssertTrue(coordinator.isPending(7))
            fresh.resolve(.success(true))
            await wait([finished])
            XCTAssertFalse(coordinator.isPending(7))
        }
    }

    @MainActor func testRefreshStartedBeforeOrDuringSaveCannotUndoItsConfirmation() async {
        let coordinator = PlannerCompletionCoordinator()
        let before = coordinator.beginRead()
        let request = HeldCompletion()
        let saved = XCTestExpectation(description: "saved")
        coordinator.submit(serverID: 3, current: false, desired: true,
            operation: { try await request.send() }, onSuccess: { _ in saved.fulfill() },
            onFailure: { _ in XCTFail() })
        let during = coordinator.beginRead()
        XCTAssertFalse(coordinator.reconcile(true, serverID: 3, read: before))
        await wait([request.started])
        request.resolve(.success(true))
        await wait([saved])
        XCTAssertTrue(coordinator.reconcile(false, serverID: 3, read: before))
        XCTAssertTrue(coordinator.reconcile(false, serverID: 3, read: during))
        // Do not permanently hide an update made from another device.
        XCTAssertFalse(coordinator.reconcile(false, serverID: 3, read: coordinator.beginRead()))
    }

    @MainActor func testFailedUndoKeepsConfirmedStateAndCanBeRetried() async {
        let coordinator = PlannerCompletionCoordinator()
        let failed = XCTestExpectation(description: "failure")
        let read = coordinator.beginRead()
        coordinator.submit(serverID: 4, current: true, desired: false,
            operation: { throw URLError(.notConnectedToInternet) },
            onSuccess: { _ in XCTFail("Must not celebrate failure") },
            onFailure: { _ in failed.fulfill() })
        await wait([failed])
        XCTAssertTrue(coordinator.reconcile(false, serverID: 4, read: read))
        XCTAssertFalse(coordinator.isPending(4))
        let retry = XCTestExpectation(description: "retry")
        XCTAssertTrue(coordinator.submit(serverID: 4, current: true, desired: false,
            operation: { false }, onSuccess: { _ in retry.fulfill() }, onFailure: { _ in XCTFail() }))
        await wait([retry])
    }

    @MainActor func testNoOpDoesNotSendOrCelebrate() {
        let coordinator = PlannerCompletionCoordinator()
        XCTAssertFalse(coordinator.submit(serverID: 9, current: true, desired: true,
            operation: { XCTFail("Redundant request"); return true },
            onSuccess: { _ in XCTFail() }, onFailure: { _ in XCTFail() }))
        XCTAssertFalse(coordinator.isPending(9))
    }
}
