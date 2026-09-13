import Foundation
import XCTest
@testable import AccountSafety

@MainActor
private final class HeldLike {
    let started = XCTestExpectation(description: "like started")
    var continuation: CheckedContinuation<SocialLikeCoordinator.Confirmation, Error>?
    func send() async throws -> SocialLikeCoordinator.Confirmation {
        try await withCheckedThrowingContinuation {
            continuation = $0
            started.fulfill()
        }
    }
}

final class SocialLikeTests: XCTestCase {
    @MainActor func testRepeatedTapSendsOnlyOnceAndAllowsUndoAfterConfirmation() async throws {
        let coordinator = SocialLikeCoordinator(), held = HeldLike()
        let first = Task { try await coordinator.submit(postID: 7) { try await held.send() } }
        await fulfillment(of: [held.started], timeout: 2)
        XCTAssertTrue(coordinator.isPending(7))
        let duplicate = try await coordinator.submit(postID: 7) {
            XCTFail("A second visible copy must not issue a request")
            return .init(liked: false, count: 0)
        }
        XCTAssertNil(duplicate)
        held.continuation?.resume(returning: .init(liked: true, count: 4))
        let saved = try await first.value
        XCTAssertEqual(saved, .init(liked: true, count: 4))
        XCTAssertFalse(coordinator.isPending(7))
        let undone = try await coordinator.submit(postID: 7) { .init(liked: false, count: 3) }
        XCTAssertEqual(undone, .init(liked: false, count: 3))
    }

    @MainActor func testReorderedDifferentPostsAndFailureDoNotInterfere() async throws {
        let coordinator = SocialLikeCoordinator(), held = HeldLike()
        let first = Task { try await coordinator.submit(postID: 1) { try await held.send() } }
        await fulfillment(of: [held.started], timeout: 2)
        let second = try await coordinator.submit(postID: 2) { .init(liked: true, count: 9) }
        XCTAssertEqual(second?.count, 9)
        held.continuation?.resume(throwing: URLError(.timedOut))
        do { _ = try await first.value; XCTFail("Expected failure") } catch {}
        XCTAssertFalse(coordinator.isPending(1))
        let retry = try await coordinator.submit(postID: 1) { .init(liked: true, count: 1) }
        XCTAssertEqual(retry?.count, 1)
    }

    @MainActor func testOldAccountSuccessCannotClearNewAccountRequest() async throws {
        let coordinator = SocialLikeCoordinator(), old = HeldLike(), new = HeldLike()
        let oldTask = Task { try await coordinator.submit(postID: 1) { try await old.send() } }
        await fulfillment(of: [old.started], timeout: 2)
        coordinator.reset()
        let newTask = Task { try await coordinator.submit(postID: 1) { try await new.send() } }
        await fulfillment(of: [new.started], timeout: 2)
        old.continuation?.resume(returning: .init(liked: true, count: 100))
        let stale = try await oldTask.value
        XCTAssertNil(stale)
        XCTAssertTrue(coordinator.isPending(1))
        new.continuation?.resume(returning: .init(liked: false, count: 1))
        let fresh = try await newTask.value
        XCTAssertEqual(fresh?.count, 1)
    }

    @MainActor func testOldAccountFailureIsIgnored() async throws {
        let coordinator = SocialLikeCoordinator(), held = HeldLike()
        let task = Task { try await coordinator.submit(postID: 1) { try await held.send() } }
        await fulfillment(of: [held.started], timeout: 2)
        coordinator.reset()
        held.continuation?.resume(throwing: URLError(.timedOut))
        let stale = try await task.value
        XCTAssertNil(stale)
    }
}
