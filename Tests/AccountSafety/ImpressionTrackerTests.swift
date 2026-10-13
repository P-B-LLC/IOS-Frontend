import Foundation
import XCTest
@testable import AccountSafety

/// What For You is told about what was on screen. The same rules as the web
/// client's tracker, so a reader is measured the same way on either.
final class ImpressionTrackerTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func at(_ milliseconds: Double) -> Date {
        start.addingTimeInterval(milliseconds / 1000)
    }

    func testAViewingRunsFromShownToHiddenAndARepeatedShownIsTheSameOne() {
        var tracker = ImpressionTracker()
        tracker.shown(1, at: at(0))
        tracker.shown(1, at: at(500))
        tracker.hidden(1, at: at(4200))
        XCTAssertEqual(tracker.pending, [
            ImpressionEvent(postID: 1, dwellMilliseconds: 4200, watchMilliseconds: nil, completed: false),
        ])
        tracker.hidden(1, at: at(9000))
        XCTAssertEqual(tracker.pending.count, 1, "hiding something not on screen does nothing")
    }

    func testDwellIsCappedAtTheServersCeilingAndNeverNegative() {
        var tracker = ImpressionTracker()
        tracker.shown(2, at: at(0))
        tracker.hidden(2, at: at(60 * 60 * 1000))
        XCTAssertEqual(tracker.pending[0].dwellMilliseconds, ImpressionTracker.maxDwellMilliseconds)
        tracker.shown(3, at: at(1000))
        tracker.hidden(3, at: at(0))
        XCTAssertEqual(tracker.pending[1].dwellMilliseconds, 0)
    }

    func testClipProgressRidesWithItsViewingAndOnlyMovesForward() {
        var tracker = ImpressionTracker()
        tracker.shown(4, at: at(0))
        tracker.watched(4, milliseconds: 3000)
        tracker.watched(4, milliseconds: 1000)
        tracker.watched(4, milliseconds: 8000, completed: true)
        tracker.watched(4, milliseconds: 2000)
        tracker.hidden(4, at: at(9000))
        XCTAssertEqual(tracker.pending[0].watchMilliseconds, 8000)
        XCTAssertTrue(tracker.pending[0].completed)
    }

    func testProgressArrivingJustAfterTheCardWentJoinsThatViewing() {
        var tracker = ImpressionTracker()
        tracker.shown(5, at: at(0))
        tracker.hidden(5, at: at(3000))
        tracker.watched(5, milliseconds: 2500, completed: true)
        XCTAssertEqual(tracker.pending[0].watchMilliseconds, 2500)
        XCTAssertTrue(tracker.pending[0].completed)
        tracker.watched(99, milliseconds: 1000)
        XCTAssertEqual(tracker.pending.count, 1, "progress for a post never counted is ignored")
        XCTAssertFalse(tracker.isOnScreen(99))
    }

    func testAWatchPositionIsCappedToo() {
        var tracker = ImpressionTracker()
        tracker.shown(6, at: at(0))
        tracker.watched(6, milliseconds: Int.max / 2)
        tracker.hidden(6, at: at(1))
        XCTAssertEqual(tracker.pending[0].watchMilliseconds, ImpressionTracker.maxWatchMilliseconds)
    }

    func testBatchesAreAtMostFiftyOldestFirst() {
        var tracker = ImpressionTracker()
        for id in 1...120 {
            tracker.shown(id, at: at(0))
            tracker.hidden(id, at: at(2000))
        }
        let first = tracker.nextBatch()
        XCTAssertEqual(first.count, 50)
        XCTAssertEqual(first.first?.postID, 1)
        XCTAssertEqual(first.last?.postID, 50)
        XCTAssertEqual(tracker.pending.count, 70)
        _ = tracker.nextBatch()
        XCTAssertEqual(tracker.nextBatch().count, 20)
        XCTAssertFalse(tracker.hasPending)
        XCTAssertTrue(tracker.nextBatch().isEmpty)
    }

    func testClosingEverythingTurnsEachOpenViewingIntoAnEvent() {
        var tracker = ImpressionTracker()
        tracker.shown(7, at: at(0))
        tracker.shown(8, at: at(1000))
        tracker.closeAll(at: at(5000))
        XCTAssertEqual(tracker.pending.map(\.postID), [7, 8])
        XCTAssertEqual(tracker.pending.map(\.dwellMilliseconds), [5000, 4000])
        XCTAssertFalse(tracker.isOnScreen(7))
        XCTAssertFalse(tracker.isOnScreen(8))
    }

    func testResetForgetsEverythingForTheNextAccount() {
        var tracker = ImpressionTracker()
        tracker.shown(9, at: at(0))
        tracker.hidden(9, at: at(10))
        tracker.shown(10, at: at(0))
        tracker.reset()
        XCTAssertFalse(tracker.hasPending)
        XCTAssertFalse(tracker.isOnScreen(10))
    }
}
