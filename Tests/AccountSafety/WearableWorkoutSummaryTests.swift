import Foundation
import XCTest
@testable import AccountSafety

final class WearableWorkoutSummaryTests: XCTestCase {
    private func summary(
        activity: WorkoutActivity = .weightlifting,
        duration: Double = 1800,
        provider: String = "apple_health",
        source: String = "apple_health",
        sourceName: String? = nil,
        distance: Decimal? = nil,
        energy: Decimal? = nil,
        averageHeartRate: Decimal? = nil,
        maxHeartRate: Decimal? = nil
    ) -> HealthWorkoutSummary {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return HealthWorkoutSummary(
            id: 8, sessionID: 11, externalID: UUID().uuidString,
            provider: provider, source: source, sourceName: sourceName,
            sourceBundleID: nil, deviceName: nil, activity: activity,
            startedAt: start, endedAt: start.addingTimeInterval(1800),
            durationSeconds: duration, distanceKilometers: distance,
            activeEnergyKilocalories: energy, averageHeartRateBPM: averageHeartRate,
            maxHeartRateBPM: maxHeartRate, updatedAt: start.addingTimeInterval(1900)
        )
    }

    func testImportedStrengthUsesRecordedDurationWithoutInventingSets() {
        let workout = summary()
        XCTAssertTrue(workout.activity.usesSets)
        XCTAssertTrue(workout.hasRecordedDuration)
        XCTAssertEqual(workout.durationSeconds, 1800)
    }

    func testEverySupportedActivityCanCarryAWatchSummary() {
        for activity in WorkoutActivity.allCases {
            let workout = summary(activity: activity)
            XCTAssertEqual(workout.activity, activity)
            XCTAssertTrue(workout.hasRecordedDuration)
        }
    }

    func testInvalidOrEmptyRecordedDurationDoesNotCountAsTraining() {
        for duration in [0.0, -1.0, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertFalse(summary(duration: duration).hasRecordedDuration)
        }
    }

    func testUnavailableMetricsRemainNilNotZero() {
        let workout = summary()
        XCTAssertNil(workout.distanceKilometers)
        XCTAssertNil(workout.activeEnergyKilocalories)
        XCTAssertNil(workout.averageHeartRateBPM)
        XCTAssertNil(workout.maxHeartRateBPM)
        XCTAssertNil(workout.deviceName)
    }

    func testReportedMetricsKeepTheirDecimalPrecision() {
        let workout = summary(
            distance: Decimal(string: "5.123"), energy: Decimal(string: "220.75"),
            averageHeartRate: Decimal(string: "121.25"), maxHeartRate: Decimal(string: "164.50")
        )
        XCTAssertEqual(workout.distanceKilometers, Decimal(string: "5.123"))
        XCTAssertEqual(workout.activeEnergyKilocalories, Decimal(string: "220.75"))
        XCTAssertEqual(workout.averageHeartRateBPM, Decimal(string: "121.25"))
        XCTAssertEqual(workout.maxHeartRateBPM, Decimal(string: "164.50"))
    }

    func testZeroReportedEnergyIsDifferentFromMissingEnergy() {
        XCTAssertEqual(summary(energy: 0).activeEnergyKilocalories, 0)
        XCTAssertNotEqual(summary(energy: 0).activeEnergyKilocalories, summary().activeEnergyKilocalories)
    }

    func testDisplayNameAloneCannotEnableGarminClassification() {
        for name in ["Garmin", "Garmin Connect", "Garmin via Apple Health"] {
            XCTAssertFalse(summary(sourceName: name).isGarminViaAppleHealth)
        }
        XCTAssertFalse(summary(provider: "other", source: "garmin").isGarminViaAppleHealth)
        XCTAssertTrue(summary(source: "garmin").isGarminViaAppleHealth)
    }

    // Source guards supplement the domain tests; they do not render SwiftUI.
    private func source(_ path: String) throws -> String {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        return try String(contentsOf: URL(fileURLWithPath: root)
            .appendingPathComponent("IOS Frontend/IOS Frontend/\(path)"), encoding: .utf8)
    }

    func testOwnerSessionReadsBackTheOptionalSummaryWithoutAffectingLegacySessions() throws {
        let model = try source("Models/PostCandidate.swift")
        XCTAssertTrue(model.contains("healthSummary: HealthWorkoutSummary? = nil"))
        XCTAssertTrue(model.contains("healthSummary.hasRecordedDuration"))
        XCTAssertTrue(model.contains("healthSummary != nil && loggedSetCount == 0"))
        XCTAssertTrue(try source("API/WorkoutAPIRepository.swift")
            .contains("session.healthSummary.map { HealthWorkoutSummary(api: $0.value1) }"))
    }

    func testHistoryAndDayAvoidZeroSetRecordsForImportedStrength() throws {
        let history = try source("Views/Workouts/ActivityHistoryViews.swift")
        let day = try source("Views/Workouts/DayWorkoutView.swift")
        XCTAssertTrue(history.contains("session.activity?.usesSets == false || session.isImportedWithoutSets"))
        XCTAssertTrue(history.contains("session.activity?.usesSets != false && !session.isImportedWithoutSets"))
        XCTAssertTrue(day.contains("workout.tracksDistance || session.isImportedWithoutSets"))
        XCTAssertTrue(day.contains("HealthWorkoutMetricsView("))
        XCTAssertTrue(history.contains("Text(\"Not reported\")"))
        XCTAssertTrue(history.contains("Label(summary.sourceDisplayName"))
    }

    func testPrivateHealthSummaryIsNotAddedToSocialPayloads() throws {
        let social = try source("API/SocialAPIRepository.swift")
        for key in ["healthSummary", "health_summary", "averageHeartRateBPM", "maxHeartRateBPM"] {
            XCTAssertFalse(social.contains(key), "Private watch metrics must not be serialized as social post content")
        }
    }
}
