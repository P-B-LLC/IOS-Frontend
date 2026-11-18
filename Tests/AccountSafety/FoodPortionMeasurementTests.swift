import Foundation
import XCTest
@testable import AccountSafety

final class FoodPortionMeasurementTests: XCTestCase {
    func testMeasurementControlsKeepSaveAndRetryGuards() throws {
        let root = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"]))
        let view = try String(contentsOf: root.appendingPathComponent("IOS Frontend/IOS Frontend/Views/Food/FoodPortionView.swift"), encoding: .utf8)
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

    func testArabicKeyboardDecimalAcrossRegionsAndNumberingSystems() {
        // Explicit numbering-system overrides keep this independent of the
        // OS/CLDR default chosen by the language-only `ar` locale.
        for identifier in ["ar", "ar_EG", "ar_SA", "ar_DZ", "ar-u-nu-latn", "ar-u-nu-arab"] {
            let locale = Locale(identifier: identifier)
            XCTAssertEqual(FoodPortionMeasurement.positive("١٫٥", locale: locale), Decimal(string: "1.5"), identifier)
            XCTAssertEqual(FoodPortionMeasurement.positive("١٢٥٫٢٥", locale: locale), Decimal(string: "125.25"), identifier)
            for invalid in ["١٬٥", "١٬٠٠٠", "١٬٠٠٠٫٥", "١٫٥٫٥", "١٫٥.٥", "١٫٥,٥", "٫", "٠٫٠", "-١٫٥", "١٫٥abc"] {
                XCTAssertNil(FoodPortionMeasurement.positive(invalid, locale: locale), "\(identifier): \(invalid)")
            }
        }
    }

    func testArabicDecimalMarkerDoesNotEnableAmbiguousGroupingAlternatives() {
        let latinArabic = Locale(identifier: "ar-u-nu-latn")
        XCTAssertEqual(FoodPortionMeasurement.positive("1.5", locale: latinArabic), Decimal(string: "1.5"))
        XCTAssertNil(FoodPortionMeasurement.positive("1,000", locale: latinArabic))
        XCTAssertNil(FoodPortionMeasurement.positive("1.000", locale: Locale(identifier: "de")))
        XCTAssertNil(FoodPortionMeasurement.positive("1,000٫5", locale: Locale(identifier: "en")))
    }

    func testKnownLabelReferenceNeedsOnlyWeightEaten() throws {
        let basis = try XCTUnwrap(FoodPortionReference(quantity: 20, unit: "g", legacyDescription: "1 tbsp (20 g)"))
        let multiplier = try XCTUnwrap(FoodPortionMeasurement.multiplier(amount: 75, measured: true,
            ounces: false, gramsPerServing: basis.quantity))
        XCTAssertEqual(multiplier, Decimal(string: "3.75"))
        XCTAssertEqual(FoodPortionMeasurement.savedMultiplier(multiplier), multiplier)
    }

    func testReferenceDoesNotGuessMassFromCountsOrLiquidVolume() {
        XCTAssertNil(FoodPortionReference(quantity: nil, unit: nil, legacyDescription: "1 banana"))
        XCTAssertNil(FoodPortionReference(quantity: nil, unit: nil, legacyDescription: "1 serving of this food entry"))
        XCTAssertNil(FoodPortionReference(quantity: 0, unit: "g", legacyDescription: "100 g"))
        XCTAssertNil(FoodPortionReference(quantity: 20, unit: "oz", legacyDescription: nil))
        XCTAssertEqual(FoodPortionReference(quantity: 250, unit: "ml", legacyDescription: nil)?.unit, "ml")
        XCTAssertEqual(FoodPortionReference(quantity: nil, unit: nil, legacyDescription: "100 g")?.quantity, 100)
    }

    func testFractionalWeightRatiosRoundToApiPrecisionBeforePreviewAndSave() {
        let raw = FoodPortionMeasurement.multiplier(amount: 73, measured: true, ounces: false, gramsPerServing: 7)!
        XCTAssertEqual(FoodPortionMeasurement.savedMultiplier(raw), Decimal(string: "10.428571"))
        XCTAssertNil(FoodPortionMeasurement.savedMultiplier(Decimal(string: "0.0000001")!))
        XCTAssertNil(FoodPortionMeasurement.savedMultiplier(.nan))
        XCTAssertNil(FoodPortionMeasurement.savedMultiplier(1001))
    }

    func testKnownZeroMacrosCanBeEditedWithoutPermissiveParsing() {
        XCTAssertEqual(FoodPortionMeasurement.nonnegative("0", locale: Locale(identifier: "en")), 0)
        XCTAssertNil(FoodPortionMeasurement.nonnegative("", locale: Locale(identifier: "en")))
        XCTAssertNil(FoodPortionMeasurement.nonnegative("12abc", locale: Locale(identifier: "en")))
        XCTAssertEqual(FoodPortionMeasurement.nonnegative("12,34", locale: Locale(identifier: "de")), Decimal(string: "12.34"))
    }

    func testServingMetadataAndNutrientsAreNotDroppedByThePortionUi() throws {
        let root = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"]))
        let picker = try String(contentsOf: root.appendingPathComponent("IOS Frontend/IOS Frontend/Views/Food/FoodPickerView.swift"), encoding: .utf8)
        let view = try String(contentsOf: root.appendingPathComponent("IOS Frontend/IOS Frontend/Views/Food/FoodPortionView.swift"), encoding: .utf8)
        XCTAssertTrue(picker.contains("food.copyForLogging()"))
        XCTAssertTrue(view.contains("FoodPortionReference(quantity: food.referenceQuantity"))
        XCTAssertTrue(view.contains("FoodPortionMeasurement.savedMultiplier"))
        XCTAssertFalse(view.contains("TextField(\"Grams in one serving\""))
    }
}
