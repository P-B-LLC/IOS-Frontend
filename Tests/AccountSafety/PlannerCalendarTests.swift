import Foundation
import XCTest
@testable import AccountSafety

final class PlannerCalendarTests: XCTestCase {
    func testOneAgendaOrdersScheduledTimesBeforeAnytimeAndKeepsTiesStable() {
        struct Item: Equatable { let title: String; let time: String? }
        let items = [Item(title: "Pool laps", time: nil),
                     Item(title: "Dinner", time: "18:00:00"),
                     Item(title: "Appointment", time: "09:00:00"),
                     Item(title: "Priority task", time: "09:00:00"),
                     Item(title: "Groceries", time: nil)]
        let result = PlannerAgendaOrder.ordered(items, time: { $0.time })
        XCTAssertEqual(result.map(\.title), ["Appointment", "Priority task", "Dinner", "Pool laps", "Groceries"])
        XCTAssertEqual(result.count, items.count)
    }

    func testEmptyAndUnscheduledAgendasKeepTheirOrder() {
        let times: [String?] = [nil, nil]
        XCTAssertEqual(PlannerAgendaOrder.ordered(times, time: { $0 }), times)
        XCTAssertEqual(PlannerAgendaOrder.ordered([String](), time: { $0 }), [])
    }

    func testHourlyAgendaKeepsOverlappingEntriesAndExactMinuteOrder() {
        struct Item { let id: Int; let time: String? }
        let items = [Item(id: 1, time: "09:45:00"), Item(id: 2, time: "09:15:00"),
                     Item(id: 3, time: "09:15:00"), Item(id: 4, time: "00:00:00"),
                     Item(id: 5, time: "23:59:59"), Item(id: 6, time: nil)]
        let groups = PlannerHourAgenda.grouped(items, time: { $0.time })
        XCTAssertEqual(groups[9]?.map(\.id), [2, 3, 1], "Overlapping tasks must not replace one another")
        XCTAssertEqual(groups[0]?.map(\.id), [4])
        XCTAssertEqual(groups[23]?.map(\.id), [5])
        XCTAssertEqual(Set(groups.values.flatMap { $0.map(\.id) }), [1, 2, 3, 4, 5])
        XCTAssertEqual(groups.values.reduce(0) { $0 + $1.count }, 5)
    }

    func testUntimedOrInvalidClocksAreNeverPlacedAtAnInventedHour() {
        let invalid: [String?] = [nil, "", "9:00", "24:00:00", "09:60:00", "09:00:60", "09:00:nan", "later"]
        for time in invalid {
            XCTAssertNil(PlannerHourAgenda.hour(from: time), "\(time ?? "nil") should stay outside the hourly grid")
        }
        XCTAssertEqual(PlannerHourAgenda.hour(from: "09:30"), 9)
        XCTAssertEqual(PlannerHourAgenda.hour(from: "23:59:59.5"), 23)
    }

    func testEmptyDayStillHasHoursAndAnAccessibleInitialPosition() {
        let empty: [String] = []
        XCTAssertTrue(PlannerHourAgenda.grouped(empty, time: { $0 }).isEmpty)
        XCTAssertEqual(PlannerHourAgenda.hours.first, 0)
        XCTAssertEqual(PlannerHourAgenda.hours.last, 23)
        XCTAssertEqual(PlannerHourAgenda.hours.count, 24)
        XCTAssertEqual(PlannerHourAgenda.initialHour(scheduledHours: [], isToday: true, currentHour: 23), 23)
        XCTAssertEqual(PlannerHourAgenda.initialHour(scheduledHours: [], isToday: false, currentHour: 23), 8)
        XCTAssertEqual(PlannerHourAgenda.initialHour(scheduledHours: [23, 9, 12], isToday: true, currentHour: 18), 9)
    }

    func testDayNavigationUsesCalendarDaysAcrossDaylightSavingAndYearEnd() throws {
        for (start, expected, elapsed) in [
            (date(2026, 3, 8), date(2026, 3, 9), 23.0 * 3600),
            (date(2026, 11, 1), date(2026, 11, 2), 25.0 * 3600),
            (date(2026, 12, 31), date(2027, 1, 1), 24.0 * 3600)
        ] {
            let next = try XCTUnwrap(PlannerHourAgenda.movingDays(1, from: start, calendar: calendar))
            XCTAssertEqual(next, expected)
            XCTAssertEqual(next.timeIntervalSince(start), elapsed)
            XCTAssertEqual(PlannerHourAgenda.movingDays(-1, from: next, calendar: calendar), start)
        }
    }

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

    func testSundayFirstHomeStripCanIncludeADayOutsideTheWorkoutWeek() throws {
        var homeCalendar = calendar
        homeCalendar.firstWeekday = 1
        let today = date(2026, 10, 28)
        let homeWeek = try XCTUnwrap(homeCalendar.dateInterval(of: .weekOfYear, for: today))
        let workoutWeek = PlannerCalendarPolicy.week(containing: today, calendar: calendar)
        let workoutSunday = try XCTUnwrap(workoutWeek.last)

        XCTAssertEqual(homeWeek.start, date(2026, 10, 25))
        XCTAssertEqual(workoutSunday, date(2026, 11, 1))
        XCTAssertEqual(calendar.component(.weekday, from: homeWeek.start),
                       calendar.component(.weekday, from: workoutSunday))
        XCTAssertFalse(workoutWeek.contains(homeWeek.start),
                       "Matching weekdays must not make October 25 use November 1's workout")
    }

    func testHomeGuardsWorkoutMarkersCardsAndNavigationByConcreteDate() throws {
        // SwiftUI is compiled by the app build, not this headless test package.
        // Keep its wiring to the date-safe store lookup under a source guard.
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"],
                                 "Run through Scripts/test-account-safety.sh to locate app sources")
        let sourceURL = URL(fileURLWithPath: root)
            .appendingPathComponent("IOS Frontend/IOS Frontend/Views/Home/GuidedHomeView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("let weekday = workouts.weekday(forDateString: PlannerStore.dateString(day))"))
        XCTAssertTrue(source.contains("workouts.weekday(forDateString: PlannerStore.dateString(selectedDate))"))
        XCTAssertFalse(source.contains("Weekday(calendarWeekday: Calendar.current.component(.weekday, from: day))"))
        XCTAssertFalse(source.contains("Weekday(calendarWeekday: Calendar.current.component(.weekday, from: selectedDate))"))
        XCTAssertTrue(source.contains("if let weekday { .workoutDay(weekday) } else { .workouts }"),
                      "An out-of-week date must not navigate to the same weekday in a different week")
    }

    func testHomeAndTrainingWeekUnionKeepsBothDisplayedWeeks() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let midweek = PlannerCalendarPolicy.homeAndTrainingWeek(containing: date(2026, 10, 28), calendar: sundayFirst)
        XCTAssertEqual(midweek.count, 8)
        XCTAssertEqual(midweek.first, date(2026, 10, 25))
        XCTAssertEqual(midweek.last, date(2026, 11, 1))

        // On Sunday the two week definitions share only that one date.
        let sunday = PlannerCalendarPolicy.homeAndTrainingWeek(containing: date(2026, 11, 1), calendar: sundayFirst)
        XCTAssertEqual(sunday.count, 13)
        XCTAssertEqual(sunday.first, date(2026, 10, 26))
        XCTAssertEqual(sunday.last, date(2026, 11, 7))

        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        XCTAssertEqual(PlannerCalendarPolicy.homeAndTrainingWeek(containing: date(2026, 10, 28), calendar: mondayFirst),
                       PlannerCalendarPolicy.week(containing: date(2026, 10, 28), calendar: mondayFirst))
    }

    func testHomeAndTrainingWeekUnionIsBoundedForEveryLocaleWeekStart() throws {
        for firstWeekday in 1...7 {
            var localeCalendar = calendar
            localeCalendar.firstWeekday = firstWeekday
            for offset in 0..<7 {
                let day = try XCTUnwrap(localeCalendar.date(byAdding: .day, value: offset, to: date(2026, 10, 26)))
                let combined = PlannerCalendarPolicy.homeAndTrainingWeek(containing: day, calendar: localeCalendar)
                let homeWeek = try XCTUnwrap(localeCalendar.dateInterval(of: .weekOfYear, for: day))
                let training = PlannerCalendarPolicy.week(containing: day, calendar: localeCalendar)
                XCTAssertTrue((7...13).contains(combined.count))
                XCTAssertEqual(combined.count, Set(combined).count)
                XCTAssertEqual(combined, combined.sorted())
                XCTAssertTrue(Set(training).isSubset(of: Set(combined)))
                for homeOffset in 0..<7 {
                    let homeDay = try XCTUnwrap(localeCalendar.date(byAdding: .day, value: homeOffset, to: homeWeek.start))
                    XCTAssertTrue(combined.contains(homeDay))
                }
            }
        }
    }

    func testHomeAndTrainingWeekUnionPreservesDatesAcrossYearAndDSTChanges() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let newYear = PlannerCalendarPolicy.homeAndTrainingWeek(containing: date(2027, 1, 1), calendar: sundayFirst)
        XCTAssertEqual(newYear.count, 8)
        XCTAssertEqual(newYear.first, date(2026, 12, 27))
        XCTAssertEqual(newYear.last, date(2027, 1, 3))

        for (day, shortOrLongDay) in [(date(2026, 3, 8), 23 * 60 * 60),
                                    (date(2026, 11, 1), 25 * 60 * 60)] {
            let combined = PlannerCalendarPolicy.homeAndTrainingWeek(containing: day, calendar: sundayFirst)
            XCTAssertEqual(combined.count, 13)
            XCTAssertTrue(combined.allSatisfy { calendar.component(.hour, from: $0) == 0 })
            let gaps = zip(combined, combined.dropFirst()).map { pair in pair.1.timeIntervalSince(pair.0) }
            XCTAssertTrue(gaps.contains(TimeInterval(shortOrLongDay)))
        }
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
        let reads = CalendarReadGate()
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
        let reads = CalendarReadGate()
        let octoberBefore = reads.begin()
        let november = reads.begin()
        let octoberAfter = reads.begin()
        XCTAssertFalse(reads.accepts(octoberBefore))
        XCTAssertFalse(reads.accepts(november))
        XCTAssertTrue(reads.accepts(octoberAfter))
    }
}
