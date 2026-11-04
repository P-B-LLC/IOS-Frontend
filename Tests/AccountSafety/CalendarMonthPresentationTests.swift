import Foundation
import XCTest
@testable import AccountSafety

final class CalendarMonthPresentationTests: XCTestCase {
    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        value.firstWeekday = firstWeekday
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testSundayFirstNovemberUsesFiveAlignedWeeks() {
        let cal = calendar()
        let days = CalendarMonthPresentation.days(in: date(2026, 11, 20, calendar: cal), calendar: cal)
        XCTAssertEqual(days.count, 35)
        XCTAssertEqual(days.first, date(2026, 11, 1, calendar: cal))
        XCTAssertEqual(days.last, date(2026, 12, 5, calendar: cal))
        XCTAssertEqual(CalendarMonthPresentation.weekdayOrder(firstWeekday: 1), [1, 2, 3, 4, 5, 6, 7])
    }

    func testMondayFirstGridKeepsAdjacentMonthDaysAligned() {
        let cal = calendar(firstWeekday: 2)
        let days = CalendarMonthPresentation.days(in: date(2026, 11, 3, calendar: cal), calendar: cal)
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(days.first, date(2026, 10, 26, calendar: cal))
        XCTAssertEqual(days.last, date(2026, 12, 6, calendar: cal))
        XCTAssertEqual(CalendarMonthPresentation.weekdayOrder(firstWeekday: 2), [2, 3, 4, 5, 6, 7, 1])
    }

    func testLeapDayAndYearBoundaryAppearExactlyOnce() {
        let cal = calendar()
        let leap = CalendarMonthPresentation.days(in: date(2024, 2, 14, calendar: cal), calendar: cal)
        XCTAssertEqual(leap.filter { cal.isDate($0, inSameDayAs: date(2024, 2, 29, calendar: cal)) }.count, 1)
        let december = CalendarMonthPresentation.days(in: date(2026, 12, 1, calendar: cal), calendar: cal)
        XCTAssertEqual(december.count % 7, 0)
        XCTAssertTrue(december.contains(date(2027, 1, 1, calendar: cal)))
    }

    func testGridUsesLocalCalendarDaysAcrossDaylightSaving() {
        let cal = calendar()
        let days = CalendarMonthPresentation.days(in: date(2026, 11, 3, calendar: cal), calendar: cal)
        for (previous, next) in zip(days, days.dropFirst()) {
            XCTAssertEqual(cal.date(byAdding: .day, value: 1, to: previous), next)
            XCTAssertEqual(cal.component(.hour, from: next), 0)
        }
        XCTAssertEqual(Set(days).count, days.count)
    }

    func testTwoPreviewsKeepCompletedItemsInPlaceAndTieOrderStable() {
        struct Item { let id: Int; let time: String?; let complete: Bool }
        let items = [Item(id: 1, time: "09:00:00", complete: true),
                     Item(id: 2, time: "09:00:00", complete: false),
                     Item(id: 3, time: "10:00:00", complete: false)]
        let preview = CalendarMonthPresentation.previews(items, time: { $0.time })
        XCTAssertEqual(preview.map(\.id), [1, 2])
        XCTAssertTrue(preview[0].complete)
        XCTAssertEqual(CalendarMonthPresentation.previewLimit, 2)
    }

    func testSharedTotalRatherThanTruncatedPayloadDrivesOverflow() {
        XCTAssertEqual(CalendarMonthPresentation.overflow(ownCount: 3, sharedTotal: 100, shown: 2), 101)
        XCTAssertEqual(CalendarMonthPresentation.overflow(ownCount: 0, sharedTotal: 4, shown: 2), 2)
        XCTAssertEqual(CalendarMonthPresentation.overflow(ownCount: 1, sharedTotal: 0, shown: 1), 0)
        XCTAssertEqual(CalendarMonthPresentation.overflow(ownCount: -1, sharedTotal: -1, shown: 2), 0)
    }

    private func source(_ path: String) throws -> String {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        return try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(path), encoding: .utf8)
    }

    func testInlineMonthPreservesTheRealDayAndOwnedCompletionData() throws {
        let view = try source("IOS Frontend/IOS Frontend/Views/Planner/PlannerView.swift")
        XCTAssertTrue(view.contains("PlannerMonthCalendar(clearedDate:"))
        XCTAssertTrue(view.contains(".safeAreaInset(edge: .top, spacing: 0) { persistentHeader"))
        XCTAssertTrue(view.contains("store.select(date)"))
        XCTAssertTrue(view.contains("reader.scrollTo(\"planner.day\", anchor: .top)"))
        XCTAssertTrue(view.contains("reader.scrollTo(\"planner.month\", anchor: .top)"))
        XCTAssertFalse(view.contains(".sheet(isPresented: $isMonthShown"))
        XCTAssertTrue(view.contains("let counts = store.taskCounts(on: store.selectedDate)"))
        XCTAssertTrue(view.contains("PlannerAgendaOrder.ordered(filtered, time: { $0.time })"))
        XCTAssertTrue(view.contains("guard showsOwnPlans else { return [] }"))
        XCTAssertTrue(view.contains("showsOwn: showsOwnPlans"))
        XCTAssertTrue(view.contains("store.setComplete(entry, !entry.isComplete)"))
    }

    func testSharedProjectionHasNoMutationOrPrivatePlannerFields() throws {
        let style = try source("IOS Frontend/IOS Frontend/Views/Planner/CalendarMonthStyle.swift")
        for forbidden in ["store.setComplete(", "store.save(", "store.delete(", "entry.notes", "entry.subtasks", "entry.workoutID"] {
            XCTAssertFalse(style.contains(forbidden))
        }
        XCTAssertTrue(style.contains("struct CalendarSharedItemRow"))
        XCTAssertTrue(style.contains("person.crop.circle"))
        XCTAssertTrue(style.contains("var schedulingTimezone: String? = nil"))
        XCTAssertTrue(style.contains("parts.append(timezone)"))
        let month = try source("IOS Frontend/IOS Frontend/Views/Planner/PlannerMonthCalendar.swift")
        XCTAssertTrue(month.contains("sharedTotal: additionalCounts[key] ?? shared.count"))
        XCTAssertTrue(month.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertTrue(month.contains("labels += own.map"))
        XCTAssertTrue(month.contains("let own = showsOwn ? store.entries(on: date) : []"))
        let schedule = try source("IOS Frontend/IOS Frontend/Views/Planner/PlannerDaySchedule.swift")
        XCTAssertTrue(schedule.contains("ForEach(PlannerHourAgenda.hours"))
        XCTAssertTrue(schedule.contains("CalendarSharedItemRow(item: shared"))
        XCTAssertTrue(schedule.contains("calendar.timeZone = TimeZone(secondsFromGMT: 0)!"))
    }
}
