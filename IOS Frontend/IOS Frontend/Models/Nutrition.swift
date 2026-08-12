//
//  Nutrition.swift
//  IOS Frontend
//
//  App-facing food tracking models. These remain separate from API DTOs so
//  they can be mapped cleanly when nutrition operations enter the OAS.
//

import Foundation

nonisolated struct NutritionAmount: Equatable, Hashable, Codable, Sendable {
    var calories: Decimal
    var proteinGrams: Decimal
    var carbohydrateGrams: Decimal
    var fatGrams: Decimal

    static let zero = NutritionAmount(
        calories: 0,
        proteinGrams: 0,
        carbohydrateGrams: 0,
        fatGrams: 0
    )

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            calories: lhs.calories + rhs.calories,
            proteinGrams: lhs.proteinGrams + rhs.proteinGrams,
            carbohydrateGrams: lhs.carbohydrateGrams + rhs.carbohydrateGrams,
            fatGrams: lhs.fatGrams + rhs.fatGrams
        )
    }

    static func * (lhs: Self, rhs: Decimal) -> Self {
        Self(
            calories: lhs.calories * rhs,
            proteinGrams: lhs.proteinGrams * rhs,
            carbohydrateGrams: lhs.carbohydrateGrams * rhs,
            fatGrams: lhs.fatGrams * rhs
        )
    }
}

nonisolated struct NutritionGoals: Equatable, Hashable, Codable, Sendable {
    var calories: Decimal
    var proteinGrams: Decimal
    var carbohydrateGrams: Decimal
    var fatGrams: Decimal

    static let `default` = NutritionGoals(
        calories: 2_000,
        proteinGrams: 150,
        carbohydrateGrams: 250,
        fatGrams: 65
    )
}

nonisolated struct FoodEntry: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var servings: Decimal
    var nutritionPerServing: NutritionAmount

    init(
        id: UUID = UUID(),
        name: String,
        servings: Decimal = 1,
        nutritionPerServing: NutritionAmount
    ) {
        self.id = id
        self.name = name
        self.servings = servings
        self.nutritionPerServing = nutritionPerServing
    }

    var totalNutrition: NutritionAmount {
        nutritionPerServing * servings
    }
}

nonisolated struct FoodMeal: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var entries: [FoodEntry]
    var isComplete: Bool

    init(
        id: UUID = UUID(),
        name: String,
        entries: [FoodEntry] = [],
        isComplete: Bool = false
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.isComplete = isComplete
    }

    var totalNutrition: NutritionAmount {
        entries.reduce(.zero) { $0 + $1.totalNutrition }
    }
}

nonisolated struct FoodTrackingDay: Equatable, Hashable, Codable, Sendable {
    let dateKey: String
    var meals: [FoodMeal]

    var totalNutrition: NutritionAmount {
        meals.reduce(.zero) { $0 + $1.totalNutrition }
    }
}

/// A reusable recipe or meal assembled from manual food entries.
/// This remains an app-facing model until the OAS defines nutrition resources.
nonisolated struct SavedFoodMeal: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var ingredients: [FoodEntry]

    init(
        id: UUID = UUID(),
        name: String,
        ingredients: [FoodEntry] = []
    ) {
        self.id = id
        self.name = name
        self.ingredients = ingredients
    }

    var totalNutrition: NutritionAmount {
        ingredients.reduce(.zero) { $0 + $1.totalNutrition }
    }
}

nonisolated extension Decimal {
    var nutritionDouble: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }

    var nutritionText: String {
        let number = NSDecimalNumber(decimal: self)
        let rounded = number.rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 1,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            )
        )
        let value = rounded.stringValue
        return value.hasSuffix(".0") ? String(value.dropLast(2)) : value
    }
}
