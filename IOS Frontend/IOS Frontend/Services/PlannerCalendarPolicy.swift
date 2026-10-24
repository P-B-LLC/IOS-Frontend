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
}

/// A response for a previously browsed month must not replace the current one.
/// The token also distinguishes two reads of the same month (A → B → A).
@MainActor
final class PlannerMonthReadGate {
    private var latest: UUID?

    func begin() -> UUID {
        let token = UUID()
        latest = token
        return token
    }

    func accepts(_ token: UUID) -> Bool { latest == token }
}
