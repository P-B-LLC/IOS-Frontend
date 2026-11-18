import Foundation

/// Presentation-only arithmetic, never recurrence materialization or progress.
nonisolated enum CalendarMonthPresentation {
    static let previewLimit = 2

    static func days(in month: Date, calendar: Calendar = .current) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let numberOfDays = ((leading + count + 6) / 7) * 7
        guard let start = calendar.date(byAdding: .day, value: -leading, to: interval.start) else { return [] }
        return (0..<numberOfDays).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func weekdayOrder(firstWeekday: Int) -> [Int] {
        let first = (1...7).contains(firstWeekday) ? firstWeekday : 1
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    static func previews<Item>(_ items: [Item], time: (Item) -> String?) -> [Item] {
        Array(PlannerAgendaOrder.ordered(items, time: time).prefix(previewLimit))
    }

    /// Shared month reads return bounded previews plus an authoritative total.
    static func overflow(ownCount: Int, sharedTotal: Int, shown: Int) -> Int {
        max(0, max(0, ownCount) + max(0, sharedTotal) - max(0, shown))
    }
}
