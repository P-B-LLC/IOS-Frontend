import Foundation

/// Display conversion only. Wire values always remain two-decimal kilograms.
nonisolated enum WorkoutWeightUnit: String, Sendable {
    case metric, imperial
    var label: String {
        self == .imperial
            ? String(localized: "lb", bundle: .app, locale: .app, comment: "Abbreviation for pounds, the unit of weight")
            : String(localized: "kg", bundle: .app, locale: .app, comment: "Abbreviation for kilograms, the unit of weight")
    }
    private var factor: Decimal { self == .imperial ? Decimal(string: "2.2046226218")! : 1 }

    func display(kilograms: String) -> String {
        guard !kilograms.isEmpty, let value = Decimal(string: kilograms) else { return kilograms }
        return rounded(value * factor)
    }

    func kilograms(display: String) -> String {
        let normalized = display.replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Decimal(string: normalized),
              normalized.range(of: #"^-?(?:\d+(?:\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil else { return normalized }
        return rounded(value / factor)
    }

    private func rounded(_ value: Decimal) -> String {
        var input = value, output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return NSDecimalNumber(decimal: output).stringValue
    }
}
