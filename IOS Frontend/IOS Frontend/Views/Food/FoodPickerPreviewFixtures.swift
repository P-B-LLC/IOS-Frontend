#if DEBUG
import Foundation

/// Illustrative, disconnected data for native visual review. The barcodes are
/// checksum-valid synthetic identities, not claims about real branded products.
/// Discovery rows intentionally include unknown nutrition: the preview must not
/// make an unhydrated identity look like a complete, loggable food.
nonisolated enum FoodPickerPreviewFixtures {
    static var candidates: [FoodCatalogueCandidate] {
        [
            FoodCatalogueCandidate(verified: rolledOats),
            FoodCatalogueCandidate(sourceID: "off:0000000000024", name: "Porridge oats", brand: "Sample Pantry"),
            FoodCatalogueCandidate(sourceID: "off:0000000000031", name: "Oat drink", brand: "Sample Pantry"),
            FoodCatalogueCandidate(sourceID: "off:0000000000048", name: "Instant oats", brand: "Sample Pantry")
        ]
    }

    static func detail(for candidate: FoodCatalogueCandidate) -> FoodDatabaseResult? {
        [rolledOats, porridgeOats, oatDrink, zeroCalorieResult]
            .first { $0.sourceID == candidate.sourceID }
    }

    /// A real zero stays distinguishable from an unknown discovery value.
    static var zeroCalorieResult: FoodDatabaseResult {
        product(code: "0000000000055", name: "Sparkling water", serving: "100 ml",
                quantity: 100, unit: "ml", nutrition: .zero)
    }

    private static var rolledOats: FoodDatabaseResult {
        product(code: "0000000000017", name: "Rolled oats · Sample Pantry", serving: "1 serving (30 g)",
                quantity: 30, unit: "g", nutrition: NutritionAmount(
                    calories: 111, proteinGrams: Decimal(string: "3.9")!,
                    carbohydrateGrams: Decimal(string: "18.3")!, fatGrams: Decimal(string: "2.1")!))
    }

    private static var porridgeOats: FoodDatabaseResult {
        product(code: "0000000000024", name: "Porridge oats · Sample Pantry", serving: "1 serving (40 g)",
                quantity: 40, unit: "g", nutrition: NutritionAmount(
                    calories: 148, proteinGrams: Decimal(string: "5.2")!,
                    carbohydrateGrams: Decimal(string: "24.4")!, fatGrams: Decimal(string: "2.8")!))
    }

    private static var oatDrink: FoodDatabaseResult {
        product(code: "0000000000031", name: "Oat drink · Sample Pantry", serving: "1 glass (250 ml)",
                quantity: 250, unit: "ml", nutrition: NutritionAmount(
                    calories: Decimal(string: "117.5")!, proteinGrams: Decimal(string: "2.5")!,
                    carbohydrateGrams: Decimal(string: "16.5")!, fatGrams: 4))
    }

    private static func product(code: String, name: String, serving: String,
                                quantity: Decimal, unit: String,
                                nutrition: NutritionAmount) -> FoodDatabaseResult {
        let sourceID = "off:" + code
        return FoodDatabaseResult(sourceID: sourceID, servingDescription: serving,
            entry: FoodEntry(name: name, nutritionPerServing: nutrition,
                sourceID: sourceID, servingDescription: serving,
                referenceQuantity: quantity, referenceUnit: unit))
    }
}
#endif
