import Foundation

/// Splits only a locale's actual day-period symbol from an already formatted
/// planner time. The original localized time remains the accessibility label.
nonisolated struct HomeSunriseClockParts {
    let clock: String
    let period: String?

    init(_ displayTime: String, locale: Locale) {
        let original = displayTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        let symbols: [String] = [formatter.amSymbol, formatter.pmSymbol].compactMap { $0 }
        for symbol in symbols where !symbol.isEmpty {
            let candidate: String
            if original.hasSuffix(symbol) {
                candidate = String(original.dropLast(symbol.count))
            } else if original.hasPrefix(symbol) {
                candidate = String(original.dropFirst(symbol.count))
            } else {
                continue
            }
            let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains) else { continue }
            clock = value
            period = symbol
            return
        }
        clock = original
        period = nil
    }
}
