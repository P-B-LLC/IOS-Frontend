import Foundation
import XCTest
@testable import AccountSafety

final class HomeSunriseClockTests: XCTestCase {
    func testEnglishTimeSeparatesItsPeriodWithoutLosingMinutes() {
        let parts = HomeSunriseClockParts("10:30\u{202F}AM", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(parts.clock, "10:30")
        XCTAssertEqual(parts.period, "AM")
    }

    func testJapanesePeriodAtTheStartIsKept() {
        let parts = HomeSunriseClockParts("午後10:30", locale: Locale(identifier: "ja_JP"))
        XCTAssertEqual(parts.clock, "10:30")
        XCTAssertEqual(parts.period, "午後")
    }

    func testArabicDigitsAndPeriodRemainIntact() {
        let parts = HomeSunriseClockParts("١٠:٣٠\u{00A0}ص", locale: Locale(identifier: "ar"))
        XCTAssertEqual(parts.clock, "١٠:٣٠")
        XCTAssertEqual(parts.period, "ص")
    }

    func testTwentyFourHourTimeDoesNotGainADayPeriod() {
        let parts = HomeSunriseClockParts("22:15", locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(parts.clock, "22:15")
        XCTAssertNil(parts.period)
    }

    func testMidnightRemainsZeroInTwentyFourHourLocales() {
        let parts = HomeSunriseClockParts("00:00", locale: Locale(identifier: "fr_FR"))
        XCTAssertEqual(parts.clock, "00:00")
        XCTAssertNil(parts.period)
    }

    func testUntimedLabelsAndWordsAreNeverParsedAsClockValues() {
        for value in ["No time set", "Anytime", "AM"] {
            let parts = HomeSunriseClockParts(value, locale: Locale(identifier: "en_US"))
            XCTAssertEqual(parts.clock, value)
            XCTAssertNil(parts.period)
        }
    }
}
