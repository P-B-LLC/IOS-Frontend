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
    /// The source and reference survive saving, recents, and recipe copies.
    /// A reference is the SAME basis as nutritionPerServing and nutrients:
    /// 20 g can mean a labelled serving; 100 g can mean a database reference.
    /// Missing metadata on historical/manual foods must never become 100 g.
    var sourceID: String?
    var servingDescription: String?
    var referenceQuantity: Decimal?
    var referenceUnit: String?
    /// Canonical nutrient keys and units are defined by the API. Absent is
    /// unknown, not zero. These amounts are per reference, like the macros.
    var nutrients: [String: Decimal]
    /// Local recovery-format version, never a wire field. Version-one drafts
    /// were originally submitted with two-decimal serving multipliers; their
    /// retry must keep that payload fingerprint after an app upgrade.
    var snapshotVersion: Int

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        name: String,
        servings: Decimal = 1,
        nutritionPerServing: NutritionAmount,
        sourceID: String? = nil,
        servingDescription: String? = nil,
        referenceQuantity: Decimal? = nil,
        referenceUnit: String? = nil,
        nutrients: [String: Decimal] = [:]
    ) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.servings = servings
        self.nutritionPerServing = nutritionPerServing
        self.sourceID = sourceID
        self.servingDescription = servingDescription
        self.referenceQuantity = referenceQuantity
        self.referenceUnit = referenceUnit
        self.nutrients = nutrients
        snapshotVersion = 2
    }

    private enum CodingKeys: String, CodingKey {
        case id, serverID, name, servings, nutritionPerServing
        case sourceID, servingDescription, referenceQuantity, referenceUnit, nutrients, snapshotVersion
    }

    /// Recovery files written before serving metadata was introduced remain
    /// readable and preserve their original identity, macros and multiplier.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        serverID = try values.decodeIfPresent(Int.self, forKey: .serverID)
        name = try values.decode(String.self, forKey: .name)
        servings = try values.decode(Decimal.self, forKey: .servings)
        nutritionPerServing = try values.decode(NutritionAmount.self, forKey: .nutritionPerServing)
        sourceID = try values.decodeIfPresent(String.self, forKey: .sourceID)
        servingDescription = try values.decodeIfPresent(String.self, forKey: .servingDescription)
        referenceQuantity = try values.decodeIfPresent(Decimal.self, forKey: .referenceQuantity)
        referenceUnit = try values.decodeIfPresent(String.self, forKey: .referenceUnit)
        nutrients = try values.decodeIfPresent([String: Decimal].self, forKey: .nutrients) ?? [:]
        snapshotVersion = try values.decodeIfPresent(Int.self, forKey: .snapshotVersion) ?? 1
    }

    var totalNutrition: NutritionAmount {
        nutritionPerServing * servings
    }

    var totalNutrients: [String: Decimal] {
        nutrients.mapValues { $0 * servings }
    }

    var hasSourceDetails: Bool {
        sourceID?.isEmpty == false || servingDescription?.isEmpty == false ||
        referenceQuantity != nil || referenceUnit?.isEmpty == false || !nutrients.isEmpty
    }

    /// A new log has a new identity but keeps the source's immutable
    /// nutrition/reference snapshot; retry keeps this copy's identity.
    func copyForLogging() -> FoodEntry {
        FoodEntry(name: name, servings: servings, nutritionPerServing: nutritionPerServing,
                  sourceID: sourceID, servingDescription: servingDescription,
                  referenceQuantity: referenceQuantity, referenceUnit: referenceUnit,
                  nutrients: nutrients)
    }

    /// Manual editors only edit the four macro figures. Renaming a food or
    /// changing its amount preserves the verified snapshot; changing those
    /// figures makes the old source/micronutrients no longer authoritative.
    mutating func preserveSourceDetails(ifNutritionMatches original: FoodEntry?) {
        sourceID = nil
        servingDescription = nil
        referenceQuantity = nil
        referenceUnit = nil
        nutrients = [:]
        guard let original, nutritionPerServing == original.nutritionPerServing else { return }
        sourceID = original.sourceID
        servingDescription = original.servingDescription
        referenceQuantity = original.referenceQuantity
        referenceUnit = original.referenceUnit
        nutrients = original.nutrients
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

    /// The name to show, in the chosen language when it is one of ours.
    ///
    /// The server names a day's slots "Meal 1" to "Meal 4", and the app names
    /// any it adds the same way, and that English is what is stored. Those
    /// default names are shown translated; a name somebody typed is shown as
    /// they typed it. `name` stays the stored value, for renaming and saving.
    var displayName: String {
        let prefix = "Meal "
        guard name.hasPrefix(prefix), let number = Int(name.dropFirst(prefix.count)) else {
            return name
        }
        return String(localized: "Meal \(number)", bundle: .app, locale: .app)
    }

    /// The display name inside a sentence ("Log meal 1"). Lower case, as the
    /// English has it, except in German, where every noun is capitalized.
    var displayNameInSentence: String {
        AppLocalization.shared.language == .german ? displayName : displayName.lowercased(with: .app)
    }
}

/// A reusable recipe or meal assembled from manual food entries.
nonisolated struct SavedFoodMeal: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    /// The backend identifier. Nil only for a recipe being written that has
    /// not been saved yet.
    var serverID: Int?
    var cookbookID: Int? = nil
    var name: String
    var ingredients: [FoodEntry]
    /// How it is made, when whoever saved it had a recipe to keep.
    ///
    /// Copied from the post it was saved from rather than looked up, so it
    /// survives that post being edited or deleted. Blank for a meal built by
    /// hand and for one saved from a post whose author wrote none.
    var cookingInstructions: String

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        name: String,
        ingredients: [FoodEntry] = [],
        cookingInstructions: String = "",
        cookbookID: Int? = nil
    ) {
        self.id = id
        self.serverID = serverID
        self.cookbookID = cookbookID
        self.name = name
        self.ingredients = ingredients
        self.cookingInstructions = cookingInstructions
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
