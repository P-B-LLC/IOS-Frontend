import Foundation
import XCTest
@testable import AccountSafety

final class DailyNutrientProgressTests: XCTestCase {
    private func definition(_ id: String) throws -> FoodNutrientDefinition {
        try XCTUnwrap(FoodNutrientDefinition.all.first { $0.id == id })
    }

    private func food(_ nutrients: [String: Decimal] = [:], servings: Decimal = 1) -> FoodEntry {
        FoodEntry(name: "Test food", servings: servings,
                  nutritionPerServing: .zero, nutrients: nutrients)
    }

    func testEachNutrientHasOneCanonicalUnitAndReference() throws {
        XCTAssertEqual(FoodNutrientDefinition.all.count, 10)
        XCTAssertEqual(Set(FoodNutrientDefinition.all.map(\.id)).count, 10)
        XCTAssertEqual(try definition("fiber_g").dailyValue, 28)
        XCTAssertEqual(try definition("vitamin_d_ug").unit, "µg")
        XCTAssertEqual(try definition("vitamin_d_ug").dailyValue, 20)
        XCTAssertEqual(try definition("calcium_mg").dailyValue, 1_300)
        XCTAssertEqual(try definition("iron_mg").dailyValue, 18)
        XCTAssertEqual(try definition("potassium_mg").dailyValue, 4_700)
        XCTAssertEqual(try definition("magnesium_mg").dailyValue, 420)
        XCTAssertEqual(try definition("vitamin_c_mg").dailyValue, 90)
    }

    func testSavedPerReferenceAmountsScaleByTheActualPortion() throws {
        let result = DailyNutrientProgress(entries: [
            food(["calcium_mg": 100], servings: Decimal(string: "1.25")!),
            food(["calcium_mg": 50], servings: 2),
        ], definition: try definition("calcium_mg"))
        XCTAssertEqual(result.knownAmount, 225)
        XCTAssertEqual(result.knownFoodCount, 2)
        XCTAssertEqual(result.totalFoodCount, 2)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.ratio, Decimal(225) / Decimal(1_300))
    }

    func testKnownZeroIsNotTreatedAsMissing() throws {
        let zero = DailyNutrientProgress(entries: [food(["fiber_g": 0])],
                                         definition: try definition("fiber_g"))
        XCTAssertEqual(zero.knownAmount, 0)
        XCTAssertEqual(zero.ratio, 0)
        XCTAssertEqual(zero.knownFoodCount, 1)
        XCTAssertTrue(zero.isComplete)
        let missing = DailyNutrientProgress(entries: [food()], definition: try definition("fiber_g"))
        XCTAssertNil(missing.knownAmount)
        XCTAssertNil(missing.ratio)
        XCTAssertFalse(missing.isComplete)
    }

    func testPartialDataSumsOnlyKnownValuesAndRetainsCoverage() throws {
        let result = DailyNutrientProgress(entries: [food(["iron_mg": 9]), food()],
                                           definition: try definition("iron_mg"))
        XCTAssertEqual(result.knownAmount, 9)
        XCTAssertEqual(result.ratio, Decimal(string: "0.5"))
        XCTAssertEqual(result.knownFoodCount, 1)
        XCTAssertEqual(result.totalFoodCount, 2)
        XCTAssertFalse(result.isComplete)
    }

    func testAnEmptyDayHasNoFabricatedCoverageOrNutrients() throws {
        let result = DailyNutrientProgress(entries: [], definition: try definition("vitamin_d_ug"))
        XCTAssertNil(result.knownAmount)
        XCTAssertNil(result.ratio)
        XCTAssertEqual(result.knownFoodCount, 0)
        XCTAssertEqual(result.totalFoodCount, 0)
        XCTAssertFalse(result.isComplete)
    }

    func testLimitsRetainOverReferenceRatiosInsteadOfReportingAWin() throws {
        let sodium = try definition("sodium_mg")
        XCTAssertEqual(sodium.direction, .limit)
        let result = DailyNutrientProgress(entries: [food(["sodium_mg": 2_760])], definition: sodium)
        XCTAssertEqual(result.ratio, Decimal(string: "1.2"))
        let saturatedFat = try definition("saturated_fat_g")
        XCTAssertEqual(saturatedFat.direction, .limit)
        XCTAssertEqual(saturatedFat.dailyValue, 20)
    }

    func testTotalSugarHasAnAmountButNoInventedDailyTarget() throws {
        let sugar = try definition("sugars_g")
        XCTAssertEqual(sugar.direction, .amount)
        XCTAssertNil(sugar.dailyValue)
        let result = DailyNutrientProgress(entries: [food(["sugars_g": 25], servings: 2)], definition: sugar)
        XCTAssertEqual(result.knownAmount, 50)
        XCTAssertNil(result.ratio)
        XCTAssertTrue(result.isComplete)
    }

    func testInvalidNutrientsAndPortionsAreExcludedNotZeroFilled() throws {
        let result = DailyNutrientProgress(entries: [
            food(["fiber_g": -1]),
            food(["fiber_g": .nan]),
            food(["fiber_g": 3], servings: 0),
            food(["fiber_g": 3], servings: -1),
            food(["fiber_g": 3], servings: .nan),
            food(["fiber_g": 3], servings: 2),
        ], definition: try definition("fiber_g"))
        XCTAssertEqual(result.knownAmount, 6)
        XCTAssertEqual(result.knownFoodCount, 1)
        XCTAssertEqual(result.totalFoodCount, 6)
        XCTAssertFalse(result.isComplete)
    }

    func testUnknownNutrientsDoNotLeakIntoAnotherProgressRow() throws {
        let result = DailyNutrientProgress(entries: [food(["not_a_nutrient": 100, "sodium_mg": 200])],
                                           definition: try definition("calcium_mg"))
        XCTAssertNil(result.knownAmount)
        XCTAssertEqual(result.knownFoodCount, 0)
    }

    func testHistoricalDraftWithoutMetadataRemainsUnknownNotZero() throws {
        let data = Data(#"{"id":"B635C6D7-E076-47C8-A845-421BB402D665","name":"Old food","servings":2,"nutritionPerServing":{"calories":100,"proteinGrams":2,"carbohydrateGrams":3,"fatGrams":4}}"#.utf8)
        let legacy = try JSONDecoder().decode(FoodEntry.self, from: data)
        XCTAssertEqual(legacy.totalNutrition.calories, 200)
        XCTAssertTrue(legacy.nutrients.isEmpty)
        let result = DailyNutrientProgress(entries: [legacy], definition: try definition("calcium_mg"))
        XCTAssertNil(result.knownAmount)
        XCTAssertFalse(result.isComplete)
    }
}
