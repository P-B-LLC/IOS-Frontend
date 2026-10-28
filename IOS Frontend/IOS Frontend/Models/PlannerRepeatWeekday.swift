import Foundation

/// Wire values follow Python weekday(): Monday=0, Sunday=6.
enum PlannerRepeatWeekday: Int, CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday
    var id: Int { rawValue }
    var title: String { Self.symbolCalendar.weekdaySymbols[symbolIndex] }
    var shortTitle: String { Self.symbolCalendar.shortWeekdaySymbols[symbolIndex] }

    static func summary(_ days: [Int]) -> String {
        let selected = allCases.filter { days.contains($0.rawValue) }
        if selected.count == 7 { return String(localized: "Every day", bundle: .app, locale: .app) }
        let list = selected.map(\.shortTitle).formatted(.list(type: .and, width: .narrow).locale(.app))
        return String(
            localized: "Every \(list)",
            bundle: .app,
            locale: .app,
            comment: "A task's repeat rule; the placeholder lists short weekday names, e.g. Mon, Fri"
        )
    }

    static func firstDate(onOrAfter date: Date, days: Set<Int>, calendar: Calendar = .current) -> Date {
        guard !days.isEmpty else { return date }
        let weekday = (calendar.component(.weekday, from: date) + 5) % 7
        let offset = days.filter { (0...6).contains($0) }.map { ($0 - weekday + 7) % 7 }.min() ?? 0
        return calendar.date(byAdding: .day, value: offset, to: date) ?? date
    }

    /// Where this day sits in `Calendar`'s symbol lists, which start on Sunday.
    private var symbolIndex: Int { (rawValue + 1) % 7 }

    /// Day names come from the calendar in the language chosen in Settings
    /// rather than being translated here.
    private static var symbolCalendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = .app
        return calendar
    }
}
