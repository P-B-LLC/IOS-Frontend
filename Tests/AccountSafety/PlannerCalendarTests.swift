import Foundation
import XCTest
@testable import AccountSafety

final class PlannerCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Chicago")!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testWeekIsMondayFirstAcrossYearBoundary() {
        let days = PlannerCalendarPolicy.week(containing: date(2027, 1, 1), calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, date(2026, 12, 28))
        XCTAssertEqual(days.last, date(2027, 1, 3))
        XCTAssertEqual(Set(days).count, 7)
    }

    func testSundayBelongsToThePrecedingMonday() {
        let days = PlannerCalendarPolicy.week(containing: date(2026, 10, 25), calendar: calendar)
        XCTAssertEqual(days.first, date(2026, 10, 19))
        XCTAssertEqual(days.last, date(2026, 10, 25))
    }

    func testWeekNavigationPreservesLocalMidnightAcrossBothDSTChanges() {
        for start in [date(2026, 3, 7), date(2026, 10, 31)] {
            let moved = PlannerCalendarPolicy.movingWeeks(1, from: start, calendar: calendar)!
            XCTAssertEqual(calendar.component(.hour, from: moved), 0)
            XCTAssertEqual(calendar.component(.weekday, from: moved), calendar.component(.weekday, from: start))
            XCTAssertEqual(PlannerCalendarPolicy.movingWeeks(-1, from: moved, calendar: calendar), start)
            XCTAssertNotEqual(moved.timeIntervalSince(start), 7 * 24 * 60 * 60)
        }
    }

    func testLeapDayIsNotSkipped() {
        let days = PlannerCalendarPolicy.week(containing: date(2028, 2, 29), calendar: calendar)
        XCTAssertTrue(days.contains(date(2028, 2, 29)))
        XCTAssertEqual(days.last, date(2028, 3, 5))
    }

    @MainActor func testOlderMonthSuccessOrFailureCannotOverwriteLatestRead() {
        let reads = PlannerMonthReadGate()
        let first = reads.begin()
        let second = reads.begin()
        var displayedMonth = "loading"
        var displayedError: String?
        if reads.accepts(second) { displayedMonth = "November" }
        if reads.accepts(first) { displayedMonth = "October" }
        if reads.accepts(first) { displayedError = "Old October request failed" }
        XCTAssertEqual(displayedMonth, "November")
        XCTAssertNil(displayedError)
        XCTAssertTrue(reads.accepts(second))
    }

    @MainActor func testReturningToTheSameMonthStillRejectsItsEarlierRequest() {
        let reads = PlannerMonthReadGate()
        let octoberBefore = reads.begin()
        let november = reads.begin()
        let octoberAfter = reads.begin()
        XCTAssertFalse(reads.accepts(octoberBefore))
        XCTAssertFalse(reads.accepts(november))
        XCTAssertTrue(reads.accepts(octoberAfter))
    }
}
