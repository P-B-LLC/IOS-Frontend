import Foundation

nonisolated enum WorkoutWidgetControls {
    struct Position: Equatable {
        let exercise: Int
        let set: Int
    }
    static func nextSet(in logged: [[Bool]]) -> Position? {
        for (exercise, sets) in logged.enumerated() {
            if let set = sets.firstIndex(of: false) { return .init(exercise: exercise, set: set) }
        }
        return nil
    }
    static func weight(_ value: String, increasing: Bool) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.isEmpty || clean.range(of: #"^-?\d+(?:\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let number = Decimal(string: clean.isEmpty ? "0" : clean, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let delta = Decimal(25) / 10
        let next = max(Decimal(-99999), min(Decimal(99999), number + (increasing ? delta : -delta)))
        return NSDecimalNumber(decimal: next).stringValue
    }
    static func reps(_ value: String, increasing: Bool) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(clean.isEmpty ? "0" : clean), (0...999).contains(number) else { return nil }
        return String(min(max(number + (increasing ? 1 : -1), 0), 999))
    }
}
