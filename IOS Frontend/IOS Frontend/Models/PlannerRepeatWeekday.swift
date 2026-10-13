import Foundation

/// Wire values follow Python weekday(): Monday=0, Sunday=6.
enum PlannerRepeatWeekday: Int, CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday
    var id: Int { rawValue }
    var title: String { ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][rawValue] }
    var shortTitle: String { String(title.prefix(3)) }

    static func summary(_ days: [Int]) -> String {
        let selected = allCases.filter { days.contains($0.rawValue) }
        return selected.count == 7 ? "Every day" : "Every " + selected.map(\.shortTitle).joined(separator: ", ")
    }

    static func firstDate(onOrAfter date: Date, days: Set<Int>, calendar: Calendar = .current) -> Date {
        guard !days.isEmpty else { return date }
        let weekday = (calendar.component(.weekday, from: date) + 5) % 7
        let offset = days.filter { (0...6).contains($0) }.map { ($0 - weekday + 7) % 7 }.min() ?? 0
        return calendar.date(byAdding: .day, value: offset, to: date) ?? date
    }
}
