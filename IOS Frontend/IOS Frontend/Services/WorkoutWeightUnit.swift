import Foundation

/// Display conversion only. Wire values always remain two-decimal kilograms.
///
/// Conversion happens once, on the way in, and the shown figure is worked out
/// again from the stored kilograms every time rather than from the last figure
/// shown. Switching units back and forth therefore never moves a recorded
/// weight, and rounding cannot build up.
nonisolated enum WorkoutWeightUnit: String, CaseIterable, Identifiable, Sendable {
    case metric, imperial

    var id: String { rawValue }

    var label: String {
        self == .imperial
            ? String(localized: "lb", bundle: .app, locale: .app, comment: "Abbreviation for pounds, the unit of weight")
            : String(localized: "kg", bundle: .app, locale: .app, comment: "Abbreviation for kilograms, the unit of weight")
    }

    var title: String {
        self == .imperial
            ? String(localized: "Pounds", bundle: .app, locale: .app, comment: "The unit of weight")
            : String(localized: "Kilograms", bundle: .app, locale: .app, comment: "The unit of weight")
    }

    var toggled: WorkoutWeightUnit { self == .metric ? .imperial : .metric }

    /// Exact by definition: an international pound is 0.45359237 kg. The
    /// rounded 2.2046 this used before was close enough to show but not to
    /// convert with, which is how 135 lb came back as 134.99.
    static let kilogramsPerPound = Decimal(string: "0.45359237")!

    /// Pounds are shown to a tenth. Kilograms are stored to a hundredth, and
    /// a hundredth of a kilogram is two hundredths of a pound, so a figure
    /// typed in pounds always comes back exactly as it was typed.
    private var displayScale: Int { self == .imperial ? 1 : 2 }

    func display(kilograms: String) -> String {
        guard !kilograms.isEmpty, let value = Decimal(string: kilograms) else { return kilograms }
        return display(kilograms: value)
    }

    func display(kilograms value: Decimal) -> String {
        let shown = self == .imperial ? value / Self.kilogramsPerPound : value
        return rounded(shown, scale: displayScale)
    }

    func kilograms(display: String) -> String {
        let normalized = display.replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Decimal(string: normalized),
              normalized.range(of: #"^-?(?:\d+(?:\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil else { return normalized }
        return rounded(self == .imperial ? value * Self.kilogramsPerPound : value, scale: 2)
    }

    /// "60 kg" or "132.3 lb".
    func formatted(kilograms value: Decimal) -> String {
        String(
            localized: "\(display(kilograms: value)) \(label)",
            bundle: .app,
            locale: .app,
            comment: "A weight: the number, then its unit, kg or lb"
        )
    }

    private func rounded(_ value: Decimal, scale: Int) -> String {
        var input = value, output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return NSDecimalNumber(decimal: output).stringValue
    }
}
