import Foundation

/// General US nutrition-label references for adults and children age four and
/// older, not personalized nutrition advice or a score of a person's health.
/// Sources: FDA Daily Values reference guide and Nutrition Facts label guide.
/// Amounts are expressed in the canonical unit identified by each API key.
nonisolated struct FoodNutrientDefinition: Identifiable, Hashable, Sendable {
    enum Direction: Hashable, Sendable {
        /// A label reference to work toward, not a reason to exceed it.
        case target
        /// A label limit: reaching/exceeding it is not an achievement.
        case limit
        /// The label has no established Daily Value (for example total sugar).
        case amount
    }

    let id: String
    let unit: String
    let dailyValue: Decimal?
    let direction: Direction

    static let all: [Self] = [
        .init(id: "fiber_g", unit: "g", dailyValue: 28, direction: .target),
        .init(id: "vitamin_d_ug", unit: "µg", dailyValue: 20, direction: .target),
        .init(id: "calcium_mg", unit: "mg", dailyValue: 1_300, direction: .target),
        .init(id: "iron_mg", unit: "mg", dailyValue: 18, direction: .target),
        .init(id: "potassium_mg", unit: "mg", dailyValue: 4_700, direction: .target),
        .init(id: "magnesium_mg", unit: "mg", dailyValue: 420, direction: .target),
        .init(id: "vitamin_c_mg", unit: "mg", dailyValue: 90, direction: .target),
        .init(id: "sodium_mg", unit: "mg", dailyValue: 2_300, direction: .limit),
        .init(id: "saturated_fat_g", unit: "g", dailyValue: 20, direction: .limit),
        .init(id: "sugars_g", unit: "g", dailyValue: nil, direction: .amount),
    ]

    /// Computed for the current app language, not cached at launch.
    var title: String {
        switch id {
        case "fiber_g": String(localized: "Dietary fiber", bundle: .app, locale: .app)
        case "vitamin_d_ug": String(localized: "Vitamin D", bundle: .app, locale: .app)
        case "calcium_mg": String(localized: "Calcium", bundle: .app, locale: .app)
        case "iron_mg": String(localized: "Iron", bundle: .app, locale: .app)
        case "potassium_mg": String(localized: "Potassium", bundle: .app, locale: .app)
        case "magnesium_mg": String(localized: "Magnesium", bundle: .app, locale: .app)
        case "vitamin_c_mg": String(localized: "Vitamin C", bundle: .app, locale: .app)
        case "sodium_mg": String(localized: "Sodium", bundle: .app, locale: .app)
        case "saturated_fat_g": String(localized: "Saturated fat", bundle: .app, locale: .app)
        case "sugars_g": String(localized: "Total sugars", bundle: .app, locale: .app)
        default: id
        }
    }
}

/// Known intake and data coverage for one nutrient. Each amount comes from the
/// food's saved per-reference snapshot multiplied by its actual portion. No
/// network reads or database queries are needed to redraw the selected day.
nonisolated struct DailyNutrientProgress: Equatable, Sendable {
    let definition: FoodNutrientDefinition
    let knownAmount: Decimal?
    let knownFoodCount: Int
    let totalFoodCount: Int

    init(entries: [FoodEntry], definition: FoodNutrientDefinition) {
        self.definition = definition
        totalFoodCount = entries.count
        var total: Decimal = 0
        var count = 0
        for entry in entries {
            guard !entry.servings.isNaN, entry.servings > 0,
                  let amount = entry.nutrients[definition.id],
                  !amount.isNaN, amount >= 0 else { continue }
            let portion = amount * entry.servings
            let combined = total + portion
            guard !portion.isNaN, portion >= 0,
                  !combined.isNaN, combined >= 0 else { continue }
            total = combined
            count += 1
        }
        knownFoodCount = count
        // A known zero has meaning. Missing values do not become a false zero.
        knownAmount = count == 0 ? nil : total
    }

    var isComplete: Bool {
        totalFoodCount > 0 && knownFoodCount == totalFoodCount
    }

    /// Not clamped, so the UI can truthfully show more than 100% of a limit.
    /// A progress bar may clamp its fill separately. Partial data is still only
    /// known intake; callers must show the coverage instead of calling it complete.
    var ratio: Decimal? {
        guard definition.direction != .amount,
              let knownAmount, let reference = definition.dailyValue,
              !reference.isNaN, reference > 0 else { return nil }
        let value = knownAmount / reference
        return value.isNaN || value < 0 ? nil : value
    }
}
