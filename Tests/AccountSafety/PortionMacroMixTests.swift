import Foundation
import XCTest
@testable import AccountSafety

final class PortionMacroMixTests: XCTestCase {
    private func amount(_ carbs: Decimal, _ fat: Decimal, _ protein: Decimal,
                        calories: Decimal = 386) -> NutritionAmount {
        NutritionAmount(calories: calories, proteinGrams: protein,
                        carbohydrateGrams: carbs, fatGrams: fat)
    }

    func testEnergySplitUsesMacroEnergyRatherThanTheLabelCalorieTotal() {
        let nutrition = amount(84, Decimal(string: "1.9")!, Decimal(string: "6.3")!)
        let mix = PortionMacroMix(nutrition)
        XCTAssertTrue(mix.hasEnergy)
        XCTAssertEqual(mix.shares[0], 336 / 378.3, accuracy: 0.000001)
        XCTAssertEqual(mix.displayedShares, [0.888, 0.045, 0.067])
        XCTAssertEqual(PortionMacroMix(amount(84, Decimal(string: "1.9")!, Decimal(string: "6.3")!, calories: 900)).shares,
                       mix.shares)
        XCTAssertEqual(nutrition.calories, 386)
    }

    func testLargerPortionsPreserveTheMix() {
        let nutrition = amount(84, Decimal(string: "1.9")!, Decimal(string: "6.3")!)
        let original = PortionMacroMix(nutrition)
        let larger = PortionMacroMix(nutrition * Decimal(string: "1.5")!)
        for index in 0..<3 { XCTAssertEqual(original.shares[index], larger.shares[index], accuracy: 0.000001) }
        XCTAssertEqual(original.displayedShares, larger.displayedShares)
    }

    func testKnownZeroMacrosDoNotDrawAFilledRingOrDivideByZero() {
        let mix = PortionMacroMix(amount(0, 0, 0, calories: 10))
        XCTAssertFalse(mix.hasEnergy)
        XCTAssertEqual(mix.shares, [0, 0, 0])
        XCTAssertEqual(mix.displayedShares, [0, 0, 0])
    }

    func testASingleMacroFillsOnlyItsOwnSegment() {
        let mix = PortionMacroMix(amount(0, 5, 0))
        XCTAssertEqual(mix.shares, [0, 1, 0])
        XCTAssertEqual(mix.displayedShares, [0, 1, 0])
        XCTAssertEqual(mix.start(at: 2), 1)
    }

    func testInvalidMacroValuesDoNotProduceMisleadingPercentages() {
        for invalid in [Decimal.nan, -1] {
            XCTAssertFalse(PortionMacroMix(amount(invalid, 1, 1)).hasEnergy)
            XCTAssertFalse(PortionMacroMix(amount(1, invalid, 1)).hasEnergy)
            XCTAssertFalse(PortionMacroMix(amount(1, 1, invalid)).hasEnergy)
        }
    }

    func testRoundingReconcilesToOneHundredPercentAndZeroStaysZero() {
        for number in 1...100 {
            let mix = PortionMacroMix(amount(Decimal(number), Decimal(number % 7), Decimal(number % 13)))
            XCTAssertEqual(mix.displayedShares.reduce(0, +), 1, accuracy: 0.000001)
            XCTAssertTrue(mix.shares.allSatisfy { $0.isFinite && (0...1).contains($0) })
            XCTAssertTrue(mix.displayedShares.allSatisfy { $0.isFinite && (0...1).contains($0) })
            for index in 0..<3 where mix.shares[index] == 0 { XCTAssertEqual(mix.displayedShares[index], 0) }
        }
    }

    func testVeryLargeFiniteValuesDoNotOverflowTheChart() {
        let mix = PortionMacroMix(amount(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude))
        XCTAssertTrue(mix.hasEnergy)
        XCTAssertEqual(mix.shares.reduce(0, +), 1, accuracy: 0.000001)
    }
}
