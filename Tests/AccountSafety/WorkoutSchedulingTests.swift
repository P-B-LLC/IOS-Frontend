import Foundation
import XCTest
@testable import AccountSafety

/// Which days a workout can be planned on, worked out in calendar days in
/// the person's own zone: never by adding 24-hour blocks, which is wrong on
/// the two days a year the clocks change and near midnight in any zone.
final class WorkoutPlanningWindowTests: XCTestCase {
    private func calendar(_ zone: String, firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func keys(_ dates: [Date], _ calendar: Calendar) -> [String] {
        dates.map { WorkoutPlanningWindow.dateString($0, calendar: calendar) }
    }

    func testTheWindowIsTodayAndTheSevenDaysAfterIt() {
        XCTAssertEqual(WorkoutPlanningWindow.daysAhead, 7)
        let calendar = calendar("America/New_York")
        let friday = date(calendar, 2026, 10, 30, 21, 25)
        XCTAssertTrue(WorkoutPlanningWindow.contains(friday, now: friday, calendar: calendar))
        XCTAssertEqual(WorkoutPlanningWindow.dateString(WorkoutPlanningWindow.lastDay(from: friday, calendar: calendar), calendar: calendar), "2026-11-06")
        XCTAssertFalse(WorkoutPlanningWindow.contains(date(calendar, 2026, 10, 29, 23, 59), now: friday, calendar: calendar), "yesterday")
        XCTAssertTrue(WorkoutPlanningWindow.contains(date(calendar, 2026, 11, 6, 23, 59), now: friday, calendar: calendar), "a week from today")
        XCTAssertFalse(WorkoutPlanningWindow.contains(date(calendar, 2026, 11, 7, 0, 0), now: friday, calendar: calendar), "eight days away")
    }

    /// Less than a day, exactly a day, more than a day, several days, and a
    /// week: every one of them can be planned, and a moment more than a week
    /// cannot. The 24-hour mark is not a boundary of anything.
    func testEveryIntervalUpToAWeekCanBePlanned() {
        let calendar = calendar("America/New_York")
        let now = date(calendar, 2026, 10, 30, 21, 25)
        let hour: TimeInterval = 3600
        let plannable: [(String, TimeInterval)] = [
            ("in an hour", hour),
            ("later tonight, under a day", 2 * hour + 30 * 60),
            ("tomorrow, under 24 hours", 20 * hour),
            ("exactly 24 hours", 24 * hour),
            ("just over 24 hours", 24 * hour + 60),
            ("two days", 48 * hour),
            ("several days", 5 * 24 * hour),
            ("six days", 6 * 24 * hour),
        ]
        for (name, interval) in plannable {
            XCTAssertTrue(WorkoutPlanningWindow.contains(now.addingTimeInterval(interval), now: now, calendar: calendar), name)
        }
        // Seven days from 21:25 on Friday is 20:25 the next Friday, not
        // 21:25: the clocks go back on Sunday, so a week here is 169 hours.
        let weekLater = calendar.date(byAdding: .day, value: 7, to: now)!
        XCTAssertEqual(weekLater.timeIntervalSince(now), 169 * hour)
        XCTAssertTrue(WorkoutPlanningWindow.contains(weekLater, now: now, calendar: calendar), "seven days")
        XCTAssertTrue(WorkoutPlanningWindow.contains(now.addingTimeInterval(7 * 24 * hour), now: now, calendar: calendar), "168 hours")
        XCTAssertFalse(WorkoutPlanningWindow.contains(calendar.date(byAdding: .day, value: 8, to: now)!, now: now, calendar: calendar), "eight days")
        XCTAssertFalse(WorkoutPlanningWindow.contains(now.addingTimeInterval(-24 * hour), now: now, calendar: calendar), "yesterday")
    }

    /// From each day of the week, the days the window reaches past Sunday:
    /// one from a Monday, all seven from a Sunday.
    func testHowMuchOfNextWeekCanBePlannedFromEachDay() {
        let calendar = calendar("Europe/Madrid")
        // 2 November 2026 is a Monday.
        for offset in 0..<7 {
            let now = date(calendar, 2026, 11, 2 + offset, 8)
            let days = WorkoutPlanningWindow.daysAfterThisWeek(from: now, calendar: calendar)
            XCTAssertEqual(days.count, offset + 1, "day \(offset)")
            XCTAssertEqual(WorkoutPlanningWindow.dateString(days[0], calendar: calendar), "2026-11-09", "always next Monday")
            XCTAssertEqual(days.last, WorkoutPlanningWindow.lastDay(from: now, calendar: calendar))
        }
    }

    func testNextWeekIsMondayToSundayWhateverTheCalendarStartsOn() {
        for firstWeekday in [1, 2, 7] {
            let calendar = calendar("America/Los_Angeles", firstWeekday: firstWeekday)
            let friday = date(calendar, 2026, 10, 30, 21)
            XCTAssertEqual(
                keys(WorkoutPlanningWindow.nextWeek(from: friday, calendar: calendar), calendar),
                ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07", "2026-11-08"],
                "first weekday \(firstWeekday)"
            )
            XCTAssertEqual(WorkoutPlanningWindow.dateString(WorkoutPlanningWindow.weekStart(containing: friday, calendar: calendar), calendar: calendar), "2026-10-26")
            // A Sunday belongs to the week that started six days before it.
            let sunday = date(calendar, 2026, 11, 1, 23, 30)
            XCTAssertEqual(WorkoutPlanningWindow.dateString(WorkoutPlanningWindow.weekStart(containing: sunday, calendar: calendar), calendar: calendar), "2026-10-26")
        }
    }

    /// The day sent is the person's, not UTC's: at 9 pm in California it is
    /// already tomorrow in UTC.
    func testTheDateSentIsTheLocalCalendarDay() {
        let pacific = calendar("America/Los_Angeles")
        let evening = date(pacific, 2026, 10, 30, 21)
        XCTAssertEqual(WorkoutPlanningWindow.dateString(evening, calendar: pacific), "2026-10-30")
        XCTAssertEqual(WorkoutPlanningWindow.dateString(evening, calendar: calendar("UTC")), "2026-10-31")
    }

    func testDaysAcrossTheClocksGoingBackAndForward() {
        // New York falls back on Sunday 1 November 2026: a 25-hour day.
        let newYork = calendar("America/New_York")
        let lateSaturday = date(newYork, 2026, 10, 31, 23, 30)
        XCTAssertEqual(
            keys((0...7).map { WorkoutPlanningWindow.day($0, from: lateSaturday, calendar: newYork) }, newYork),
            ["2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07"]
        )
        XCTAssertEqual(WorkoutPlanningWindow.dateString(WorkoutPlanningWindow.lastDay(from: lateSaturday, calendar: newYork), calendar: newYork), "2026-11-07")
        // London springs forward on Sunday 29 March 2026: a 23-hour day.
        let london = calendar("Europe/London")
        let lateSaturdayInMarch = date(london, 2026, 3, 28, 23, 30)
        XCTAssertEqual(WorkoutPlanningWindow.dateString(WorkoutPlanningWindow.day(1, from: lateSaturdayInMarch, calendar: london), calendar: london), "2026-03-29")
        XCTAssertEqual(WorkoutPlanningWindow.dateString(WorkoutPlanningWindow.lastDay(from: lateSaturdayInMarch, calendar: london), calendar: london), "2026-04-04")
        XCTAssertTrue(WorkoutPlanningWindow.contains(date(london, 2026, 4, 4, 23, 59), now: lateSaturdayInMarch, calendar: london))
        XCTAssertFalse(WorkoutPlanningWindow.contains(date(london, 2026, 4, 5, 0, 1), now: lateSaturdayInMarch, calendar: london))
    }

    /// Zones at the edges of the clock, a half-hour zone, and Chile, where
    /// the clocks spring forward at midnight so that day has no 00:00.
    func testEveryZoneGetsSevenConsecutiveDays() {
        let zones = ["Pacific/Kiritimati", "Pacific/Pago_Pago", "Asia/Kolkata", "Australia/Lord_Howe",
                     "America/Santiago", "America/St_Johns", "UTC"]
        for zone in zones {
            let calendar = calendar(zone)
            // Saturday 5 September 2026: Chile skips Sunday's midnight.
            let now = date(calendar, 2026, 9, 5, 22)
            let days = (0...7).map { WorkoutPlanningWindow.day($0, from: now, calendar: calendar) }
            XCTAssertEqual(
                keys(days, calendar),
                ["2026-09-05", "2026-09-06", "2026-09-07", "2026-09-08", "2026-09-09", "2026-09-10", "2026-09-11", "2026-09-12"],
                zone
            )
            XCTAssertEqual(keys(WorkoutPlanningWindow.daysAfterThisWeek(from: now, calendar: calendar), calendar),
                           ["2026-09-07", "2026-09-08", "2026-09-09", "2026-09-10", "2026-09-11", "2026-09-12"], zone)
            for day in days {
                XCTAssertTrue(WorkoutPlanningWindow.contains(day, now: now, calendar: calendar), "\(zone) \(day)")
            }
        }
    }
}

/// Every activity can be written down after the fact, the same way, and a
/// session that has not finished yet cannot.
final class EveryActivityLogsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_409_900) // 30 Oct 2026, 21:25 in New York

    func testEveryActivityLogsWithOnlyItsDuration() throws {
        XCTAssertEqual(WorkoutActivity.allCases.count, 51)
        for activity in WorkoutActivity.allCases {
            var draft = ActivityLogDraft(activity: activity, endedAt: now)
            draft.setDuration(minutes: 45)
            draft.perceivedEffort = 41
            draft.calories = "5"
            draft.notes = " Fine "
            let entry = try draft.validated(now: now).get()
            XCTAssertEqual(entry.activity, activity)
            XCTAssertEqual(entry.workoutName, activity.title, "a blank name is the activity's own")
            XCTAssertEqual(entry.durationSeconds, 2700)
            XCTAssertEqual(entry.startedAt, now.addingTimeInterval(-2700))
            XCTAssertEqual(entry.perceivedEffort, 41)
            XCTAssertEqual(entry.caloriesKilocalories, 5)
            XCTAssertEqual(entry.notes, "Fine")
        }
    }

    /// Finished less than a day ago, exactly a day ago, or days ago: all of
    /// them can be logged. Finishing in the future cannot, past the few
    /// minutes a phone's clock may run ahead.
    func testWhenItFinished() throws {
        let hour: TimeInterval = 3600
        for (name, ago) in [("just now", 0.0), ("an hour ago", hour), ("under a day", 23 * hour),
                            ("exactly a day", 24 * hour), ("over a day", 25 * hour), ("several days", 5 * 24 * hour)] {
            var draft = ActivityLogDraft(activity: .tennis, endedAt: now.addingTimeInterval(-ago))
            draft.setDuration(minutes: 60)
            XCTAssertNoThrow(try draft.validated(now: now).get(), name)
        }
        var soon = ActivityLogDraft(activity: .tennis, endedAt: now.addingTimeInterval(4 * 60))
        soon.setDuration(minutes: 60)
        XCTAssertNoThrow(try soon.validated(now: now).get(), "a clock a few minutes fast")
        var later = ActivityLogDraft(activity: .tennis, endedAt: now.addingTimeInterval(hour))
        later.setDuration(minutes: 60)
        XCTAssertEqual(later.validated(now: now).failure, .startsInFuture)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
