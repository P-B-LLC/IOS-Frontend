import Foundation

/// API times are literal HH:mm:ss values, never localized AM/PM labels.
/// Equal-time and anytime items retain their existing priority/server order.
nonisolated enum PlannerAgendaOrder {
    static func ordered<Entry>(_ entries: [Entry], time: (Entry) -> String?) -> [Entry] {
        entries.enumerated().sorted { left, right in
            let lhs = time(left.element), rhs = time(right.element)
            switch (lhs, rhs) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return left.offset < right.offset
            }
        }.map(\.element)
    }
}

/// An hourly agenda groups by the literal API clock, not an invented date in
/// the current time zone. Empty hours remain available, including on DST days.
nonisolated enum PlannerHourAgenda {
    static let hours = Array(0..<24)

    static func hour(from time: String?) -> Int? {
        guard let time else { return nil }
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), (0..<24).contains(hour),
              let minute = Int(parts[1]), (0..<60).contains(minute) else { return nil }
        if parts.count == 3 {
            guard let second = Double(parts[2]), second.isFinite,
                  second >= 0, second < 60 else { return nil }
        }
        return hour
    }

    static func grouped<Entry>(_ entries: [Entry], time: (Entry) -> String?) -> [Int: [Entry]] {
        var result: [Int: [Entry]] = [:]
        for entry in PlannerAgendaOrder.ordered(entries, time: time) {
            guard let hour = hour(from: time(entry)) else { continue }
            result[hour, default: []].append(entry)
        }
        return result
    }

    static func initialHour(scheduledHours: [Int], isToday: Bool, currentHour: Int) -> Int {
        if let first = scheduledHours.filter({ hours.contains($0) }).min() { return first }
        return isToday ? min(23, max(0, currentHour)) : 8
    }

    static func movingDays(_ offset: Int, from date: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))
    }
}

/// Calendar arithmetic stays date-based across DST and year boundaries.
nonisolated enum PlannerCalendarPolicy {
    static func week(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -offset, to: day) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    static func movingWeeks(_ offset: Int, from date: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .weekOfYear, value: offset, to: calendar.startOfDay(for: date))
    }

    /// Keep Home's locale-based week and Training's Monday-based week loaded
    /// even when Calendar is browsing a different month. This bounded set must
    /// not expand into every date between today and the browsed month.
    static func homeAndTrainingWeek(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let training = week(containing: date, calendar: calendar)
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return training }
        let home = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
        return Set(training + home).sorted()
    }
}
