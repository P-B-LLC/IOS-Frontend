//
//  Nutrition.swift
//  IOS Frontend
//
//  App-facing food tracking models. Kept separate from the generated API DTOs
//  so the screens are not written against a shape the contract chooses; every
//  value in them is mapped from the server by FoodAPIRepository.
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
    /// The backend identifier. Nil only for a food being typed that has not
    /// been saved yet.
    var serverID: Int?
    var name: String
    var servings: Decimal
    var nutritionPerServing: NutritionAmount

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        name: String,
        servings: Decimal = 1,
        nutritionPerServing: NutritionAmount
    ) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.servings = servings
        self.nutritionPerServing = nutritionPerServing
    }

    var totalNutrition: NutritionAmount {
        nutritionPerServing * servings
    }
}

extension UUID {
    /// The same id every time for a given server row.
    ///
    /// Rows decoded from the server used to mint a fresh UUID on each read,
    /// so refetching a day renamed every meal in it. Anything holding an id
    /// across that refetch lost what it was pointing at -- the open meal
    /// page most of all, which drew "Meal Not Found" over a meal that was
    /// still sitting there. Applying a saved meal refetches the day, which
    /// is how a successful action ended on an error screen.
    ///
    /// Derived rather than random: the same server id has to produce the
    /// same UUID on this launch and the next. The value is only ever
    /// compared, never parsed, so packing the integer into the low eight
    /// bytes is enough.
    static func stable(forServerID serverID: Int) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: UInt64(bitPattern: Int64(serverID)).bigEndian) { raw in
            bytes.replaceSubrange(8..<16, with: raw)
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

nonisolated struct FoodMeal: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    /// The backend identifier. A meal only ever comes into being on the
    /// server, so this is nil only for the sample data behind a preview.
    var serverID: Int?
    var name: String
    var entries: [FoodEntry]

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        name: String,
        entries: [FoodEntry] = []
    ) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.entries = entries
    }

    var totalNutrition: NutritionAmount {
        entries.reduce(.zero) { $0 + $1.totalNutrition }
    }
}

/// A reusable recipe or meal assembled from manual food entries.
nonisolated struct SavedFoodMeal: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    /// The backend identifier. Nil only for a recipe being written that has
    /// not been saved yet.
    var serverID: Int?
    var name: String
    var ingredients: [FoodEntry]

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        name: String,
        ingredients: [FoodEntry] = []
    ) {
        self.id = id
        self.serverID = serverID
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
