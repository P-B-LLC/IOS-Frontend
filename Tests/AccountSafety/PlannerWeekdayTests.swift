import Foundation
import XCTest
@testable import AccountSafety

final class PlannerWeekdayTests: XCTestCase {
    func testWeekdayValuesAndSummaryAreStable() {
        XCTAssertEqual(PlannerRepeatWeekday.monday.rawValue, 0)
        XCTAssertEqual(PlannerRepeatWeekday.sunday.rawValue, 6)
        XCTAssertEqual(PlannerRepeatWeekday.summary([4, 0]), "Every Mon, Fri")
        XCTAssertEqual(PlannerRepeatWeekday.summary([6, 0, 2]), "Every Mon, Wed, Sun")
        XCTAssertEqual(PlannerRepeatWeekday.summary(Array(0...6)), "Every day")
    }

    func testFirstOccurrenceHandlesWeekBoundaryAndDaylightSaving() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!
        let next = PlannerRepeatWeekday.firstDate(onOrAfter: saturday, days: [0, 4], calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: next), 2)
        XCTAssertEqual(calendar.component(.month, from: next), 11)
        XCTAssertEqual(calendar.component(.hour, from: next), 12)
        XCTAssertEqual(PlannerRepeatWeekday.firstDate(onOrAfter: next, days: [0, 4], calendar: calendar), next)
    }
}
