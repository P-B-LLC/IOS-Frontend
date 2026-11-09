import Foundation
import XCTest
@testable import AccountSafety

final class PlannerScheduledMomentTests: XCTestCase {
    func testWallClockStaysAtNineWhileUTCOffsetChanges() throws {
        let before = try XCTUnwrap(PlannerScheduledMoment.resolve(day: "2026-03-07", time: "09:00:00", zoneIdentifier: "America/New_York"))
        let after = try XCTUnwrap(PlannerScheduledMoment.resolve(day: "2026-03-08", time: "09:00:00", zoneIdentifier: "America/New_York"))
        XCTAssertEqual(after.timeIntervalSince(before), 23 * 3600)
    }

    func testSavedZoneWinsOverDeviceZone() throws {
        let first = PlannerScheduledMoment.resolve(day: "2026-11-04", time: "10:00:00", zoneIdentifier: "America/Chicago", fallbackZone: TimeZone(identifier: "Asia/Tokyo")!)
        let second = PlannerScheduledMoment.resolve(day: "2026-11-04", time: "10:00:00", zoneIdentifier: "America/Chicago", fallbackZone: .gmt)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
    }

    func testSecondsArePreserved() throws {
        let moment = try XCTUnwrap(PlannerScheduledMoment.resolve(day: "2026-11-04", time: "09:00:45", zoneIdentifier: "UTC"))
        XCTAssertEqual(moment, ISO8601DateFormatter().date(from: "2026-11-04T09:00:45Z"))
    }

    func testSpringGapMovesForwardAndAutumnFoldChoosesFirst() throws {
        let gap = try XCTUnwrap(PlannerScheduledMoment.resolve(day: "2026-03-08", time: "02:30:00", zoneIdentifier: "America/New_York"))
        let fold = try XCTUnwrap(PlannerScheduledMoment.resolve(day: "2026-11-01", time: "01:30:00", zoneIdentifier: "America/New_York"))
        XCTAssertEqual(gap, ISO8601DateFormatter().date(from: "2026-03-08T07:30:00Z"))
        XCTAssertEqual(fold, ISO8601DateFormatter().date(from: "2026-11-01T05:30:00Z"))
    }

    func testUnknownOrMalformedScheduleDoesNotInventAnInstant() {
        XCTAssertNil(PlannerScheduledMoment.resolve(day: "2026-02-30", time: "10:00:00", zoneIdentifier: "UTC"))
        XCTAssertNil(PlannerScheduledMoment.resolve(day: "2026-11-04", time: nil, zoneIdentifier: "UTC"))
        XCTAssertNil(PlannerScheduledMoment.resolve(day: "2026-11-04", time: "24:30", zoneIdentifier: "UTC"))
        XCTAssertNil(PlannerScheduledMoment.resolve(day: "2026-11-04", time: "10:00", zoneIdentifier: "not/a-zone"))
    }
}
