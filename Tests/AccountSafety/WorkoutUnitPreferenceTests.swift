import Foundation
import XCTest
@testable import AccountSafety

@MainActor
final class WorkoutUnitPreferenceTests: XCTestCase {
    private enum SaveFailure: Error { case unavailable }

    private final class DeferredSaver: WorkoutWeightUnitSaving {
        private(set) var requested: [WorkoutWeightUnit] = []
        private var completions: [CheckedContinuation<WorkoutWeightUnit, Error>] = []

        func savePreferredWeightUnit(_ unit: WorkoutWeightUnit) async throws -> WorkoutWeightUnit {
            requested.append(unit)
            return try await withCheckedThrowingContinuation { completions.append($0) }
        }

        func succeed(_ unit: WorkoutWeightUnit, request: Int = 0) {
            completions[request].resume(returning: unit)
        }

        func fail(request: Int = 0) {
            completions[request].resume(throwing: SaveFailure.unavailable)
        }
    }

    private func preferences() -> WorkoutPreferences {
        // No rest settings are changed by these tests; the named suite keeps
        // any defaults read isolated from the developer's actual settings.
        let defaults = UserDefaults(suiteName: "WorkoutUnitPreferenceTests.\(UUID().uuidString)")!
        let preferences = WorkoutPreferences(defaults: defaults)
        preferences.adoptAccountUnit(.metric)
        return preferences
    }

    private func waitForRequests(_ count: Int, from saver: DeferredSaver) async {
        for _ in 0..<100 where saver.requested.count < count { await Task.yield() }
        XCTAssertEqual(saver.requested.count, count)
    }

    func testQuickSwitchIsTemporaryAndDoesNotChangeTheAccountDefault() {
        let preferences = preferences()
        preferences.useTemporarily(.imperial)
        XCTAssertEqual(preferences.weightUnit, .imperial)
        XCTAssertEqual(preferences.defaultWeightUnit, .metric)
        XCTAssertTrue(preferences.isUsingTemporaryUnit)
        XCTAssertFalse(preferences.isSavingUnit)
        preferences.useTemporarily(.metric)
        XCTAssertNil(preferences.temporaryWeightUnit)
        XCTAssertEqual(preferences.weightUnit, .metric)
    }

    func testAReadOfTheAccountDoesNotEraseTheTemporaryChoice() {
        let preferences = preferences()
        preferences.useTemporarily(.imperial)
        preferences.adoptAccountUnit(.metric)
        XCTAssertEqual(preferences.weightUnit, .imperial)
        preferences.adoptAccountUnit(.imperial)
        XCTAssertNil(preferences.temporaryWeightUnit)
        XCTAssertEqual(preferences.defaultWeightUnit, .imperial)
    }

    func testDefaultIsNotClaimedSavedUntilTheServerConfirms() async {
        let preferences = preferences(), saver = DeferredSaver()
        let task = Task { await preferences.makeDefault(.imperial, using: saver) }
        await waitForRequests(1, from: saver)
        XCTAssertTrue(preferences.isSavingUnit)
        XCTAssertEqual(preferences.weightUnit, .imperial)
        XCTAssertEqual(preferences.defaultWeightUnit, .metric)
        saver.succeed(.imperial)
        await task.value
        XCTAssertFalse(preferences.isSavingUnit)
        XCTAssertNil(preferences.unitError)
        XCTAssertNil(preferences.temporaryWeightUnit)
        XCTAssertEqual(preferences.defaultWeightUnit, .imperial)
    }

    func testFailedSaveKeepsTheDisplayedUnitAndAllowsRetry() async {
        let preferences = preferences(), saver = DeferredSaver()
        let first = Task { await preferences.makeDefault(.imperial, using: saver) }
        await waitForRequests(1, from: saver)
        saver.fail()
        await first.value
        XCTAssertEqual(preferences.defaultWeightUnit, .metric)
        XCTAssertEqual(preferences.weightUnit, .imperial)
        XCTAssertNotNil(preferences.unitError)
        XCTAssertFalse(preferences.isSavingUnit)

        let retry = Task { await preferences.makeDefault(.imperial, using: saver) }
        await waitForRequests(2, from: saver)
        XCTAssertNil(preferences.unitError)
        saver.succeed(.imperial, request: 1)
        await retry.value
        XCTAssertEqual(preferences.defaultWeightUnit, .imperial)
        XCTAssertNil(preferences.unitError)
    }

    func testRepeatedSaveTapDoesNotSendAnotherRequest() async {
        let preferences = preferences(), saver = DeferredSaver()
        let first = Task { await preferences.makeDefault(.imperial, using: saver) }
        await waitForRequests(1, from: saver)
        await preferences.makeDefault(.metric, using: saver)
        XCTAssertEqual(saver.requested, [.imperial])
        XCTAssertEqual(preferences.weightUnit, .imperial)
        saver.succeed(.imperial)
        await first.value
    }

    func testLatestDisplayChoiceSurvivesAnEarlierSaveResponse() async {
        let preferences = preferences(), saver = DeferredSaver()
        let task = Task { await preferences.makeDefault(.imperial, using: saver) }
        await waitForRequests(1, from: saver)
        preferences.useTemporarily(.metric)
        saver.succeed(.imperial)
        await task.value
        XCTAssertEqual(preferences.defaultWeightUnit, .imperial)
        XCTAssertEqual(preferences.weightUnit, .metric)
        XCTAssertEqual(preferences.temporaryWeightUnit, .metric)
    }

    func testServerResponseIsAuthoritativeWithoutChangingTheDisplayedChoice() async {
        let preferences = preferences(), saver = DeferredSaver()
        let task = Task { await preferences.makeDefault(.imperial, using: saver) }
        await waitForRequests(1, from: saver)
        saver.succeed(.metric)
        await task.value
        XCTAssertEqual(preferences.defaultWeightUnit, .metric)
        XCTAssertEqual(preferences.weightUnit, .imperial)
    }

    func testOldAccountSuccessCannotAffectTheNextAccount() async {
        let preferences = preferences(), saver = DeferredSaver()
        let task = Task { await preferences.makeDefault(.imperial, using: saver) }
        await waitForRequests(1, from: saver)
        preferences.reset()
        preferences.adoptAccountUnit(.metric)
        saver.succeed(.imperial)
        await task.value
        XCTAssertEqual(preferences.defaultWeightUnit, .metric)
        XCTAssertEqual(preferences.weightUnit, .metric)
        XCTAssertNil(preferences.unitError)
        XCTAssertFalse(preferences.isSavingUnit)
    }

    func testOldAccountFailureDoesNotShowAnErrorForTheNextAccount() async {
        let preferences = preferences(), saver = DeferredSaver()
        let task = Task { await preferences.makeDefault(.imperial, using: saver) }
        await waitForRequests(1, from: saver)
        preferences.reset()
        preferences.adoptAccountUnit(.imperial)
        saver.fail()
        await task.value
        XCTAssertEqual(preferences.defaultWeightUnit, .imperial)
        XCTAssertNil(preferences.unitError)
        XCTAssertFalse(preferences.isSavingUnit)
    }

    func testAnOldCompletionCannotUnlockANewAccountsPendingSave() async {
        let preferences = preferences(), saver = DeferredSaver()
        let old = Task { await preferences.makeDefault(.imperial, using: saver) }
        await waitForRequests(1, from: saver)
        preferences.reset()
        preferences.adoptAccountUnit(.imperial)
        let current = Task { await preferences.makeDefault(.metric, using: saver) }
        await waitForRequests(2, from: saver)
        saver.succeed(.imperial)
        await old.value
        XCTAssertTrue(preferences.isSavingUnit)
        XCTAssertEqual(preferences.weightUnit, .metric)
        saver.succeed(.metric, request: 1)
        await current.value
        XCTAssertFalse(preferences.isSavingUnit)
        XCTAssertEqual(preferences.defaultWeightUnit, .metric)
    }

    func testInitialAccountReadCannotOverwriteAFreshlyConfirmedSave() async {
        let preferences = preferences(), saver = DeferredSaver()
        let initialRead = preferences.accountUnitReadRevision
        let task = Task { await preferences.makeDefault(.imperial, using: saver) }
        await waitForRequests(1, from: saver)
        saver.succeed(.imperial)
        await task.value
        preferences.adoptAccountUnit(.metric, ifUnchangedSince: initialRead)
        XCTAssertEqual(preferences.defaultWeightUnit, .imperial)
        XCTAssertEqual(preferences.weightUnit, .imperial)
    }

    func testCurrentAccountReadMayCompleteWhileSaveIsPending() async {
        let preferences = preferences(), saver = DeferredSaver()
        let initialRead = preferences.accountUnitReadRevision
        let task = Task { await preferences.makeDefault(.imperial, using: saver) }
        await waitForRequests(1, from: saver)
        preferences.adoptAccountUnit(.metric, ifUnchangedSince: initialRead)
        XCTAssertEqual(preferences.defaultWeightUnit, .metric)
        XCTAssertEqual(preferences.weightUnit, .imperial)
        saver.succeed(.imperial)
        await task.value
        XCTAssertEqual(preferences.defaultWeightUnit, .imperial)
    }

    func testResetInvalidatesAnEarlierAccountsInitialRead() {
        let preferences = preferences()
        let oldRead = preferences.accountUnitReadRevision
        preferences.reset()
        preferences.adoptAccountUnit(.imperial, ifUnchangedSince: oldRead)
        XCTAssertEqual(preferences.defaultWeightUnit, .metric)
        XCTAssertFalse(preferences.hasLoadedUnit)
    }

    func testSwitchingOnlyRendersCanonicalWeightWithoutConversionDrift() {
        let stored = WorkoutWeightUnit.imperial.kilograms(display: "135")
        XCTAssertEqual(stored, "61.23")
        for _ in 0..<100 {
            XCTAssertEqual(WorkoutWeightUnit.metric.display(kilograms: stored), "61.23")
            XCTAssertEqual(WorkoutWeightUnit.imperial.display(kilograms: stored), "135")
        }
        XCTAssertEqual(stored, "61.23")
    }

    func testSwitchingNeverMakesAnInvalidDraftLookLikeAValidWeight() {
        for value in ["", "12junk", "-", ".", "1..2", "NaN", "Infinity"] {
            XCTAssertEqual(WorkoutWeightUnit.metric.display(kilograms: value), value)
            XCTAssertEqual(WorkoutWeightUnit.imperial.display(kilograms: value), value)
        }
        XCTAssertEqual(WorkoutWeightUnit.metric.kilograms(display: "12,5"), "12.5")
        XCTAssertEqual(WorkoutWeightUnit.imperial.display(kilograms: "60"), "132.3")
        XCTAssertEqual(WorkoutWeightUnit.metric.display(kilograms: "0"), "0")
    }

    // These guards verify that the tested conversion/preferences are wired
    // into the real editing surfaces. Native UI tests still exercise taps.
    func testBuilderKeepsRawTypingUntilAUnitSwitchAndEndsKeyboardEditingFirst() throws {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        let source = try String(contentsOf: URL(fileURLWithPath: root)
            .appendingPathComponent("IOS Frontend/IOS Frontend/Views/Workouts/GuidedWorkoutBuilder.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("@State private var targetWeightInputs: [UUID: String]"))
        XCTAssertTrue(source.contains("targetWeightInputs[exercise.id] = value"))
        XCTAssertTrue(source.contains("targetWeightInputs.removeAll()"))
        XCTAssertTrue(source.contains("WorkoutWeightUnitControl(onWillChange:"))
        XCTAssertTrue(source.contains("#selector(UIResponder.resignFirstResponder)"))
        XCTAssertTrue(source.contains("store.preferences.weightUnit.kilograms(display: trimmed)"))
    }

    func testSessionUsesCanonicalWeightAndInvalidatesOnlyTheDisplayCache() throws {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        let directory = URL(fileURLWithPath: root)
            .appendingPathComponent("IOS Frontend/IOS Frontend/Views/Workouts/Session")
        let screen = try String(contentsOf: directory.appendingPathComponent("ActiveLiftingSessionView.swift"), encoding: .utf8)
        let card = try String(contentsOf: directory.appendingPathComponent("SessionExerciseCard.swift"), encoding: .utf8)
        XCTAssertTrue(screen.contains(".onChange(of: store.preferences.weightUnit)"))
        XCTAssertTrue(screen.contains("weightInputs = [:]"))
        XCTAssertTrue(card.contains("onWillChange: { focusedField.wrappedValue = nil }"))
        XCTAssertTrue(card.contains("weightInputs[set.id] ?? unit.display(kilograms: set.weightKilograms)"))
        XCTAssertTrue(card.contains("weightKilograms: unit.kilograms(display: value)"))
    }
}
