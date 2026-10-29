import Foundation
import XCTest
@testable import AccountSafety

final class FoodPortionMeasurementTests: XCTestCase {
    func testMeasurementControlsKeepSaveAndRetryGuards() throws {
        let root = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"]))
        let view = try String(contentsOf: root.appendingPathComponent("IOS Frontend/IOS Frontend/Views/Food/FoodPickerView.swift"), encoding: .utf8)
        XCTAssertTrue(view.contains(".disabled(isSaving || lockedForRetry)"))
        XCTAssertTrue(view.contains(".disabled(isSaving || servings == nil)"))
        XCTAssertTrue(view.contains("entry.servings = servings"))
        XCTAssertTrue(view.contains("FoodPortionMeasurement.multiplier"))
        XCTAssertTrue(view.contains(".grouping(.never)"))
    }

    func testWeightAndServingsHaveTheSameMultiplier() {
        XCTAssertEqual(FoodPortionMeasurement.multiplier(amount: 125, measured: true,
            ounces: false, gramsPerServing: 100), Decimal(string: "1.25"))
        XCTAssertEqual(FoodPortionMeasurement.multiplier(amount: Decimal(string: "1.25")!,
            measured: false, ounces: false, gramsPerServing: nil), Decimal(string: "1.25"))
    }
    func testOuncesAndExplicitServingWeight() {
        XCTAssertEqual(FoodPortionMeasurement.multiplier(amount: 1, measured: true,
            ounces: true, gramsPerServing: FoodPortionMeasurement.gramsPerOunce), 1)
        XCTAssertEqual(FoodPortionMeasurement.multiplier(amount: 60, measured: true,
            ounces: false, gramsPerServing: 30), 2)
        XCTAssertNil(FoodPortionMeasurement.multiplier(amount: 60, measured: true,
            ounces: false, gramsPerServing: nil))
        XCTAssertNil(FoodPortionMeasurement.multiplier(amount: 60, measured: true,
            ounces: false, gramsPerServing: 0))
    }
    func testStrictLocalizedQuantityValidation() {
        XCTAssertEqual(FoodPortionMeasurement.positive("1,5", locale: Locale(identifier: "de")), Decimal(string: "1.5"))
        XCTAssertEqual(FoodPortionMeasurement.positive("١٫٥", locale: Locale(identifier: "ar")), Decimal(string: "1.5"))
        XCTAssertEqual(FoodPortionMeasurement.positive("१.५", locale: Locale(identifier: "hi")), Decimal(string: "1.5"))
        for value in ["", "0", "-1", "NaN", "1abc", "1.2.3", "100001", ".", "1,000", "½", "²"] {
            XCTAssertNil(FoodPortionMeasurement.positive(value, locale: Locale(identifier: "en")))
        }
        XCTAssertNil(FoodPortionMeasurement.multiplier(amount: 1001, measured: false,
            ounces: false, gramsPerServing: nil))
    }
}
