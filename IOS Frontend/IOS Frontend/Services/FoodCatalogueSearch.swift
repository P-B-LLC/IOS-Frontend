import Foundation

/// Search identities are not loggable nutrition. Only a product-detail result
/// has an explicit serving basis and can be offered to the portion screen.
nonisolated struct FoodCatalogueCandidate: Identifiable, Hashable, Sendable {
    let sourceID: String
    let name: String
    let brand: String
    let verifiedResult: FoodDatabaseResult?

    init(sourceID: String, name: String, brand: String) {
        self.sourceID = sourceID
        self.name = name
        self.brand = brand
        verifiedResult = nil
    }

    init(verified result: FoodDatabaseResult) {
        sourceID = result.sourceID
        name = result.entry.name
        brand = ""
        verifiedResult = result
    }

    var id: String { sourceID }
    var title: String {
        let label = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, !name.localizedCaseInsensitiveContains(label) else { return name }
        return "\(name) · \(label)"
    }
}

nonisolated enum FoodCataloguePolicy {
    /// An older Rytivo version has no discovery route. Other errors must not
    /// silently issue a second upstream search, especially throttles/auth.
    static func allowsLegacyFallback(statusCode: Int) -> Bool { statusCode == 404 }

    static func barcode(sourceID: String) -> String? {
        guard sourceID.hasPrefix("off:"),
              let code = FoodBarcode.validated(String(sourceID.dropFirst(4))),
              sourceID == "off:" + code else { return nil }
        return code
    }

    /// OFF labels can exceed the diary field's documented 150-code-point
    /// limit. Keep the full discovery label, but use a valid saved snapshot.
    static func diaryName(_ title: String) -> String {
        String(String.UnicodeScalarView(title.unicodeScalars.prefix(150)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func failure(statusCode: Int, retryAfter: String?) -> FoodCatalogueFailure? {
        if statusCode == 401 { return .sessionExpired }
        if statusCode == 429 || (statusCode == 503 && retryAfter?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) {
            return .busy
        }
        return nil
    }

    /// Corrupt or absent nutrients are never replaced with zero. The older
    /// generic diary mapper's default is appropriate for a typed entry, not
    /// for claiming an external product's nutrition has been verified.
    static func nutrition(calories: String, protein: String, carbs: String, fat: String) -> NutritionAmount? {
        func number(_ text: String) -> Decimal? {
            guard let match = text.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression),
                  match.lowerBound == text.startIndex, match.upperBound == text.endIndex,
                  let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
                  !value.isNaN, value >= 0 else { return nil }
            return value
        }
        guard let calories = number(calories), let protein = number(protein),
              let carbs = number(carbs), let fat = number(fat) else { return nil }
        return NutritionAmount(calories: calories, proteinGrams: protein, carbohydrateGrams: carbs, fatGrams: fat)
    }
}

nonisolated enum FoodCatalogueFailure: Error, Equatable, Sendable {
    case busy
    case sessionExpired
}

/// A complete product detail: nutrition plus its explicit serving basis.
nonisolated struct FoodDatabaseResult: Identifiable, Hashable, Sendable {
    let sourceID: String
    let servingDescription: String
    let entry: FoodEntry

    var id: String { sourceID }
}

/// Shared diary/catalogue snapshot mapping. Dictionary values use canonical
/// API units (g, mg or ug in the key), not the contributor's OFF input unit.
nonisolated enum FoodSnapshotPolicy {
    static let nutrientKeys: Set<String> = [
        "fiber_g", "saturated_fat_g", "sugars_g", "sodium_mg", "potassium_mg",
        "calcium_mg", "iron_mg", "magnesium_mg", "vitamin_c_mg", "vitamin_d_ug"
    ]

    static func decimal(_ text: String?) -> Decimal? {
        guard let text,
              let match = text.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression),
              match.lowerBound == text.startIndex, match.upperBound == text.endIndex,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, value >= 0 else { return nil }
        return value
    }

    static func nutrients(_ values: [String: String]?) -> [String: Decimal] {
        (values ?? [:]).reduce(into: [:]) { result, pair in
            guard nutrientKeys.contains(pair.key), let value = decimal(pair.value) else { return }
            result[pair.key] = value
        }
    }

    static func attaching(
        to food: FoodEntry, sourceID: String?, servingDescription: String?,
        referenceQuantity: String?, referenceUnit: String?, nutrients: [String: String]?
    ) -> FoodEntry {
        var food = food
        let source = sourceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        food.sourceID = source.flatMap { FoodCataloguePolicy.barcode(sourceID: $0) == nil ? nil : $0 }
        let description = servingDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        food.servingDescription = description?.isEmpty == false ? description : nil
        if let value = decimal(referenceQuantity), value > 0,
           referenceUnit == "g" || referenceUnit == "ml" {
            food.referenceQuantity = value
            food.referenceUnit = referenceUnit
        } else {
            food.referenceQuantity = nil
            food.referenceUnit = nil
        }
        food.nutrients = Self.nutrients(nutrients)
        return food
    }
}
