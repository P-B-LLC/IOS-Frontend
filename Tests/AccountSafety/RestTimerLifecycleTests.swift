import Foundation
import XCTest
@testable import AccountSafety

final class RestTimerLifecycleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func timer(seconds: TimeInterval = 45) -> RestTimer {
        .start(seconds: seconds, exerciseID: UUID(), at: start)
    }

    func testCompletionNoticeExpiresExactlyTenSecondsAfterRestEnds() {
        let rest = timer()
        XCTAssertEqual(RestTimer.finishedBannerSeconds, 10)
        XCTAssertEqual(rest.finishedBannerDismissalDate, start.addingTimeInterval(55))
        XCTAssertFalse(rest.isFinishedBannerExpired(at: start.addingTimeInterval(44)))
        XCTAssertFalse(rest.isFinishedBannerExpired(at: start.addingTimeInterval(45)))
        XCTAssertFalse(rest.isFinishedBannerExpired(at: start.addingTimeInterval(54.999)))
        XCTAssertTrue(rest.isFinishedBannerExpired(at: start.addingTimeInterval(55)))
        XCTAssertTrue(rest.isFinishedBannerExpired(at: start.addingTimeInterval(500)))
    }

    func testCompletionProgressUsesTheSameDeadline() {
        let rest = timer()
        XCTAssertEqual(rest.finishedBannerProgress(at: start), 1)
        XCTAssertEqual(rest.finishedBannerProgress(at: start.addingTimeInterval(45)), 1)
        XCTAssertEqual(rest.finishedBannerProgress(at: start.addingTimeInterval(49)), 0.6, accuracy: 0.001)
        XCTAssertEqual(rest.finishedBannerProgress(at: start.addingTimeInterval(55)), 0)
        XCTAssertEqual(rest.finishedBannerProgress(at: start.addingTimeInterval(500)), 0)
    }

    func testReturningDuringTheNoticeOnlyKeepsItsRemainingTime() throws {
        let restored = try JSONDecoder().decode(RestTimer.self, from: JSONEncoder().encode(timer()))
        let returnedAt = start.addingTimeInterval(52)
        XCTAssertFalse(restored.isFinishedBannerExpired(at: returnedAt))
        XCTAssertEqual(restored.finishedBannerProgress(at: returnedAt), 0.3, accuracy: 0.001)
        XCTAssertTrue(restored.isFinishedBannerExpired(at: returnedAt.addingTimeInterval(3)))
    }

    func testRelaunchAfterTheDeadlineDoesNotReplayTheNotice() throws {
        let original = timer()
        let restored = try JSONDecoder().decode(RestTimer.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.finishedBannerDismissalDate, original.finishedBannerDismissalDate)
        XCTAssertTrue(restored.isFinishedBannerExpired(at: start.addingTimeInterval(600)))
        XCTAssertTrue(restored.canDismissFinishedBanner(matching: original, at: start.addingTimeInterval(600)))
    }

    func testPausedTimerHasNoCompletionDeadlineAndNeverAutoDismisses() {
        let beforePause = timer()
        var paused = beforePause
        paused.pause(at: start.addingTimeInterval(20))
        XCTAssertNil(paused.finishedBannerDismissalDate)
        XCTAssertFalse(paused.isFinishedBannerExpired(at: start.addingTimeInterval(600)))
        XCTAssertFalse(paused.canDismissFinishedBanner(matching: beforePause, at: start.addingTimeInterval(600)))
        XCTAssertFalse(paused.canDismissFinishedBanner(matching: paused, at: start.addingTimeInterval(600)))
        XCTAssertEqual(paused.finishedBannerProgress(at: start.addingTimeInterval(600)), 0)
    }

    func testResumingMovesBothTheRestAndNoticeDeadlines() {
        var rest = timer()
        rest.pause(at: start.addingTimeInterval(20))
        rest.resume(at: start.addingTimeInterval(100))
        XCTAssertEqual(rest.endsAt, start.addingTimeInterval(125))
        XCTAssertEqual(rest.finishedBannerDismissalDate, start.addingTimeInterval(135))
        XCTAssertFalse(rest.isFinishedBannerExpired(at: start.addingTimeInterval(134)))
        XCTAssertTrue(rest.isFinishedBannerExpired(at: start.addingTimeInterval(135)))
    }

    func testOldCallbackCannotDismissAReplacementEvenWithTheSameEndDate() {
        let old = timer(), replacement = timer()
        XCTAssertEqual(old.endsAt, replacement.endsAt)
        XCTAssertNotEqual(old.id, replacement.id)
        XCTAssertFalse(replacement.canDismissFinishedBanner(matching: old, at: start.addingTimeInterval(100)))
        XCTAssertTrue(replacement.canDismissFinishedBanner(matching: replacement, at: start.addingTimeInterval(100)))
    }

    func testResetKeepsItsIDButRejectsThePreviousDeadlineCallback() {
        let old = timer()
        var reset = old
        reset.reset(at: start.addingTimeInterval(50))
        XCTAssertEqual(old.id, reset.id)
        XCTAssertEqual(reset.finishedBannerDismissalDate, start.addingTimeInterval(105))
        XCTAssertFalse(reset.canDismissFinishedBanner(matching: old, at: start.addingTimeInterval(55)))
        XCTAssertFalse(reset.canDismissFinishedBanner(matching: old, at: start.addingTimeInterval(200)))
        XCTAssertTrue(reset.canDismissFinishedBanner(matching: reset, at: start.addingTimeInterval(105)))
    }

    func testAddingTimeInvalidatesThePreviousCallback() {
        let old = timer()
        var adjusted = old
        adjusted.adjust(by: 15, at: start.addingTimeInterval(30))
        XCTAssertEqual(adjusted.id, old.id)
        XCTAssertEqual(adjusted.finishedBannerDismissalDate, start.addingTimeInterval(70))
        XCTAssertFalse(adjusted.canDismissFinishedBanner(matching: old, at: start.addingTimeInterval(55)))
        XCTAssertFalse(adjusted.canDismissFinishedBanner(matching: old, at: start.addingTimeInterval(100)))
        XCTAssertTrue(adjusted.canDismissFinishedBanner(matching: adjusted, at: start.addingTimeInterval(70)))
    }

    func testSubtractingPastZeroStartsTheNoticeWindowAtThatMoment() {
        var rest = timer()
        rest.adjust(by: -90, at: start.addingTimeInterval(20))
        XCTAssertEqual(rest.phase(at: start.addingTimeInterval(20)), .finished)
        XCTAssertEqual(rest.finishedBannerDismissalDate, start.addingTimeInterval(30))
        XCTAssertFalse(rest.isFinishedBannerExpired(at: start.addingTimeInterval(29)))
        XCTAssertTrue(rest.isFinishedBannerExpired(at: start.addingTimeInterval(30)))
    }

    func testExtendingAnAlreadyFinishedRestCreatesANewNoticeWindow() {
        let old = timer()
        var rest = old
        rest.adjust(by: 15, at: start.addingTimeInterval(50))
        XCTAssertEqual(rest.phase(at: start.addingTimeInterval(50)), .running)
        XCTAssertEqual(rest.finishedBannerDismissalDate, start.addingTimeInterval(75))
        XCTAssertFalse(rest.canDismissFinishedBanner(matching: old, at: start.addingTimeInterval(100)))
    }

    // These source guards verify production wiring, not a rendered simulator.
    private func source(_ path: String) throws -> String {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        return try String(contentsOf: URL(fileURLWithPath: root)
            .appendingPathComponent("IOS Frontend/IOS Frontend/\(path)"), encoding: .utf8)
    }

    func testStoreOwnsExpiryAndFencesDelayedCallbacks() throws {
        let store = try source("Stores/WorkoutStore.swift")
        XCTAssertTrue(store.contains("scheduleRestBannerExpiry()"))
        XCTAssertTrue(store.contains("restBannerExpiryTask?.cancel()"))
        XCTAssertTrue(store.contains("guard key != restBannerExpiryKey else { return }"))
        XCTAssertTrue(store.contains("while !Task.isCancelled {\n                    let delay = deadline.timeIntervalSinceNow"))
        XCTAssertTrue(store.contains("self.connectionGeneration == key.generation"))
        XCTAssertTrue(store.contains("self.activeSession?.serverID == key.sessionID"))
        XCTAssertTrue(store.contains("self.dismissExpiredRestBanner(matching: key.timer)"))
        XCTAssertTrue(store.contains("timer.canDismissFinishedBanner(matching: expected ?? timer, at: now)"))
        XCTAssertTrue(try source("IOS_FrontendApp.swift").contains("workoutStore.dismissExpiredRestBanner()"))
    }

    func testNoticeNeverFlashesOrAnnouncesAnExpiredRestOnReturn() throws {
        let view = try source("Views/Workouts/Session/RestTimerBar.swift")
        XCTAssertTrue(view.contains("if timer.isFinishedBannerExpired(at: now)"))
        XCTAssertTrue(view.contains("!timer.isFinishedBannerExpired() else { return }"))
        XCTAssertTrue(view.contains(".task(id: timer)"))
        XCTAssertTrue(view.contains("store.dismissFinishedRest(matching: timer)"))
        XCTAssertTrue(view.contains("RestCompletionBanner(progress: timer.finishedBannerProgress(at: now))"))
        XCTAssertTrue(view.contains(".accessibilityLabel(\"Dismiss\")"))
        XCTAssertTrue(view.contains(".frame(minWidth: 44, minHeight: 44)"))
    }
}
