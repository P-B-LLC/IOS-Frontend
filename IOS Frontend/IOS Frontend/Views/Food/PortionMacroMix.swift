import Foundation

/// Presentation only: normalized macro energy, ordered carbs, fat, protein.
/// The displayed calorie total always comes from NutritionAmount.calories.
nonisolated struct PortionMacroMix {
    let shares: [Double]
    let displayedShares: [Double]
    let hasEnergy: Bool

    init(_ nutrition: NutritionAmount) {
        let energies = [
            NSDecimalNumber(decimal: nutrition.carbohydrateGrams).doubleValue * 4,
            NSDecimalNumber(decimal: nutrition.fatGrams).doubleValue * 9,
            NSDecimalNumber(decimal: nutrition.proteinGrams).doubleValue * 4
        ]
        let total = energies.reduce(0, +)
        guard energies.allSatisfy({ $0.isFinite && $0 >= 0 }), total.isFinite, total > 0 else {
            shares = [0, 0, 0]
            displayedShares = [0, 0, 0]
            hasEnergy = false
            return
        }
        hasEnergy = true
        let fractions = energies.map { $0 / total }
        shares = fractions
        // Distribute rounding remainders so the visible tenths sum to 100%.
        let scaled = fractions.map { $0 * 1000 }
        var tenths = scaled.map { Int($0.rounded(.down)) }
        let ranked = (0..<3).sorted {
            let first = scaled[$0] - Double(tenths[$0])
            let second = scaled[$1] - Double(tenths[$1])
            return first == second ? $0 < $1 : first > second
        }
        for index in ranked.prefix(max(0, 1000 - tenths.reduce(0, +))) { tenths[index] += 1 }
        displayedShares = tenths.map { Double($0) / 1000 }
    }

    func start(at index: Int) -> Double {
        shares.prefix(index).reduce(0, +)
    }
}
