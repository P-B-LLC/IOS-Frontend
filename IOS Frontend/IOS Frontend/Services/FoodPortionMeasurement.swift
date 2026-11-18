import Foundation

/// Converts UI quantities to the catalogue's nutrition multiplier. A mass is
/// never inferred from a serving name or from liquid volume.
nonisolated enum FoodPortionMeasurement {
    static let gramsPerOunce = Decimal(string: "28.349523125")!

    static func positive(_ text: String, locale: Locale) -> Decimal? {
        guard let value = nonnegative(text, locale: locale, maximum: 100000), value > 0 else { return nil }
        return value
    }

    static func nonnegative(_ text: String, locale: Locale,
                            maximum: Decimal = Decimal(string: "999999.99")!) -> Decimal? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        // An Arabic keyboard can emit U+066B even when the selected locale
        // uses Latin digits and a period (including some `ar` defaults).
        // This is explicitly a decimal mark, not the distinct U+066C group
        // separator. Normalize it without accepting ambiguous comma/dot
        // alternatives or relaxing the single-separator/digits-only checks.
        let decimalInput = input.replacingOccurrences(of: "\u{066B}", with: separator)
        let parts = decimalInput.components(separatedBy: separator)
        guard parts.count <= 2, !input.isEmpty,
              parts.contains(where: { !$0.isEmpty }),
              parts.allSatisfy({ $0.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) } }) else { return nil }
        // Decimal's parsing of localized digits varies by Foundation version.
        // Normalize decimal digits only, after rejecting groups, signs and junk.
        let normalized = parts.map { part in
            part.compactMap { $0.wholeNumberValue }.map(String.init).joined()
        }.joined(separator: ".")
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, value >= 0, value <= maximum else { return nil }
        return value
    }

    static func multiplier(amount: Decimal, measured: Bool, ounces: Bool,
                           gramsPerServing: Decimal?) -> Decimal? {
        guard !amount.isNaN, amount > 0, amount <= 100000 else { return nil }
        var result = amount
        if measured {
            guard let basis = gramsPerServing, !basis.isNaN, basis > 0,
                  basis <= 100000 else { return nil }
            result = amount * (ounces ? gramsPerOunce : 1) / basis
        }
        return !result.isNaN && result > 0 && result <= 1000 ? result : nil
    }

    /// Preview exactly the six-decimal multiplier the API can save. A ratio
    /// such as 73 g / 7 g must not fail serialization or silently become zero.
    static func savedMultiplier(_ value: Decimal) -> Decimal? {
        guard !value.isNaN, value > 0, value <= 1000 else { return nil }
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 6, .plain)
        return rounded >= Decimal(string: "0.000001")! && rounded <= 1000 ? rounded : nil
    }
}

/// Nutrition's explicit reference amount, not a guess from a food name or
/// from millilitres. Legacy 100 g/ml descriptions are unambiguous references.
nonisolated struct FoodPortionReference: Equatable, Sendable {
    let quantity: Decimal
    let unit: String

    init?(quantity: Decimal?, unit: String?, legacyDescription: String?) {
        if quantity != nil || (unit?.isEmpty == false) {
            guard let quantity, !quantity.isNaN, quantity > 0, quantity <= 100000,
                  let unit, unit == "g" || unit == "ml" else { return nil }
            self.quantity = quantity
            self.unit = unit
        } else {
            switch legacyDescription?.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "100 g": self.quantity = 100; self.unit = "g"
            case "100 ml": self.quantity = 100; self.unit = "ml"
            default: return nil
            }
        }
    }
}
