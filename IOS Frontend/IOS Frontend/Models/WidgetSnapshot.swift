import Foundation

/// Deliberately contains no credentials, account identifiers, photos or HealthKit data.
/// This file is compiled into both the app and its widget extension.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let group = "group.com.pbllc.rytivo"
    static let filename = "today-widget.json"
    var updatedAt: Date
    var day: String
    var tasks: [Item]?
    var nutrition: Nutrition?

    struct Item: Codable, Equatable, Sendable {
        var title: String
        var complete: Bool
        var workout: Bool
        var completable: Bool
        var stepsDone: Int
        var stepsTotal: Int
    }

    struct Nutrition: Codable, Equatable, Sendable {
        var calories: Decimal
        var calorieGoal: Decimal
        var protein: Decimal
        var proteinGoal: Decimal
        var carbs: Decimal
        var carbsGoal: Decimal
        var fat: Decimal
        var fatGoal: Decimal
    }

    static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func isCurrent(at date: Date) -> Bool {
        day == Self.dayKey(date) && updatedAt <= date && date.timeIntervalSince(updatedAt) < 24 * 3600
    }

    static func read(from url: URL?, now: Date = Date()) -> Self? {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              snapshot.isCurrent(at: now) else { return nil }
        return snapshot
    }

    static func progress(_ amount: Decimal, toward goal: Decimal) -> Double {
        guard goal > 0 else { return 0 }
        let result = NSDecimalNumber(decimal: amount / goal).doubleValue
        return result.isFinite ? min(max(result, 0), 1) : 0
    }
}
