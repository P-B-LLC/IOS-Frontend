import Foundation
import XCTest
@testable import AccountSafety

/// What a connected workout says it came from, and how import batches add up.
final class HealthSourceNamingTests: XCTestCase {
    private func summary(provider: String = "apple_health", source: String = "apple_health",
                         sourceName: String? = nil, duration: Double = 600) -> HealthWorkoutSummary {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return HealthWorkoutSummary(
            id: 1, sessionID: 2, externalID: "x", provider: provider, source: source, sourceName: sourceName,
            sourceBundleID: nil, deviceName: nil, activity: .running, startedAt: start,
            endedAt: start.addingTimeInterval(600), durationSeconds: duration, distanceKilometers: nil,
            activeEnergyKilocalories: nil, averageHeartRateBPM: nil, maxHeartRateBPM: nil, updatedAt: start)
    }

    func testANamedSourceIsShownTrimmed() {
        XCTAssertEqual(summary(sourceName: "  Sam's Apple Watch \n").sourceDisplayName, "Sam's Apple Watch")
    }

    func testAMissingOrBlankSourceNameFallsBackToAppleHealth() {
        let fallback = summary().sourceDisplayName
        XCTAssertFalse(fallback.isEmpty)
        for name in [nil, "", "   ", "\n\t"] as [String?] {
            XCTAssertEqual(summary(sourceName: name).sourceDisplayName, fallback, String(describing: name))
        }
    }

    func testGarminThroughAppleHealthIsNamedAsSuchWhateverTheDeviceSays() {
        let garmin = summary(source: "garmin", sourceName: "Forerunner 965")
        XCTAssertTrue(garmin.isGarminViaAppleHealth)
        XCTAssertNotEqual(garmin.sourceDisplayName, "Forerunner 965")
        XCTAssertNotEqual(garmin.sourceDisplayName, summary().sourceDisplayName)
    }

    func testAnUnknownProviderIsNeverClassifiedAsGarminViaAppleHealth() {
        for provider in ["garmin", "", "APPLE_HEALTH", "strava"] {
            XCTAssertFalse(summary(provider: provider, source: "garmin").isGarminViaAppleHealth, provider)
        }
    }

    func testOnlyAFinitePositiveDurationCountsAsRecorded() {
        for duration in [0, -1, .nan, .infinity, -.infinity] as [Double] {
            XCTAssertFalse(summary(duration: duration).hasRecordedDuration, "\(duration)")
        }
        XCTAssertTrue(summary(duration: 0.5).hasRecordedDuration)
    }

    func testImportBatchesAddUpFieldByField() {
        let first = HealthImportSummary(imported: 3, skippedOverlapping: 1, alreadyImported: 2, updated: 1, linked: 0)
        let second = HealthImportSummary(imported: 0, skippedOverlapping: 2, alreadyImported: 5, updated: 0, linked: 4)
        XCTAssertEqual(first.adding(second),
                       HealthImportSummary(imported: 3, skippedOverlapping: 3, alreadyImported: 7, updated: 1, linked: 4))
    }

    func testNothingIsTheIdentityForAddingBatches() {
        let batch = HealthImportSummary(imported: 4, skippedOverlapping: 0, alreadyImported: 1, updated: 2, linked: 1)
        XCTAssertEqual(HealthImportSummary.nothing.adding(batch), batch)
        XCTAssertEqual(batch.adding(.nothing), batch)
        XCTAssertEqual(HealthImportSummary.nothing.adding(.nothing), .nothing)
    }
}
