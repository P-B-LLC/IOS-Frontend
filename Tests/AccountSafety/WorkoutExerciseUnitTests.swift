import Foundation
import XCTest
@testable import AccountSafety

final class WorkoutExerciseUnitTests: XCTestCase {
    private func session(serverID: Int = 4242) -> ActiveWorkoutSession {
        // The same catalog exercise may appear twice. Each session relation
        // and local row has its own identity, sets and display choice.
        let rows = (0..<2).map { index in
            SessionExerciseDraft(
                id: UUID(), exerciseServerID: 11, sessionExerciseID: 101 + index,
                name: "Bench Press",
                sets: [
                    WorkoutSetDraft(serverID: 900 + index, setNumber: 1,
                                    weightKilograms: "60", reps: "8", isLogged: true),
                    WorkoutSetDraft(setNumber: 2, weightKilograms: "", reps: "")
                ],
                workoutExerciseID: 10 + index, restSeconds: 60, supersetGroup: 1,
                targetReps: 8, targetWeightKilograms: "60"
            )
        }
        var session = ActiveWorkoutSession(
            id: UUID(), serverID: serverID, day: .monday,
            workoutID: UUID(), workoutServerID: 7, workoutName: "Push Day",
            workoutType: .lifting, startedAt: Date(timeIntervalSince1970: 1_000),
            exercises: rows,
            restTimer: .start(seconds: 60, exerciseID: rows[0].id, at: Date(timeIntervalSince1970: 1_100)),
            focusedExerciseID: rows[0].id
        )
        session.plan = session.structure
        return session
    }

    @discardableResult
    private func change(_ session: inout ActiveWorkoutSession, row: Int, to unit: WorkoutWeightUnit) -> Bool {
        session.setExerciseDisplayUnit(unit, on: session.day, sessionID: session.serverID,
                                       exerciseID: session.exercises[row].id)
    }

    func testSelectingPoundsChangesOnlyThatExerciseEvenForDuplicateCatalogRows() {
        var session = session()
        let sibling = session.exercises[1]
        XCTAssertTrue(change(&session, row: 0, to: .imperial))
        XCTAssertEqual(session.exercises[0].weightUnit(default: .metric), .imperial)
        XCTAssertEqual(session.exercises[1].weightUnit(default: .metric), .metric)
        XCTAssertEqual(session.exercises[1], sibling)
        XCTAssertEqual(session.exercises[0].exerciseServerID, session.exercises[1].exerciseServerID)
    }

    func testEachExerciseCanBeChangedIndependently() {
        var session = session()
        change(&session, row: 0, to: .imperial)
        change(&session, row: 1, to: .imperial)
        change(&session, row: 0, to: .metric)
        XCTAssertEqual(session.exercises.map(\.displayUnit), [.metric, .imperial])
    }

    func testUnitChangesNeverMutateSetsTargetsPlanRestOrFocus() {
        var session = session()
        session.exercises[0].sets[1].weightKilograms = "12junk"
        let original = session
        for _ in 0..<50 {
            change(&session, row: 0, to: .imperial)
            change(&session, row: 0, to: .metric)
        }
        XCTAssertEqual(session.exercises.map(\.sets), original.exercises.map(\.sets))
        XCTAssertEqual(session.exercises.map(\.targetWeightKilograms), original.exercises.map(\.targetWeightKilograms))
        XCTAssertEqual(session.exercises.map(\.targetReps), original.exercises.map(\.targetReps))
        XCTAssertEqual(session.exercises.map(\.supersetGroup), original.exercises.map(\.supersetGroup))
        XCTAssertEqual(session.restTimer, original.restTimer)
        XCTAssertEqual(session.focusedExerciseID, original.focusedExerciseID)
        XCTAssertEqual(session.loggedVolumeKilograms, original.loggedVolumeKilograms)
        XCTAssertEqual(session.plan, original.plan)
        XCTAssertTrue(session.structureChanges.isEmpty)
        XCTAssertFalse(session.orderNeedsSync)
    }

    func testSelectingTheSameUnitIsANoOp() {
        var session = session()
        change(&session, row: 0, to: .imperial)
        let original = session
        XCTAssertFalse(change(&session, row: 0, to: .imperial))
        XCTAssertEqual(session, original)
    }

    func testStaleSessionDayAndDeletedExerciseAreRejected() {
        var session = session()
        let original = session, id = session.exercises[0].id
        XCTAssertFalse(session.setExerciseDisplayUnit(.imperial, on: .monday, sessionID: 9999, exerciseID: id))
        XCTAssertFalse(session.setExerciseDisplayUnit(.imperial, on: .tuesday, sessionID: session.serverID, exerciseID: id))
        XCTAssertFalse(session.setExerciseDisplayUnit(.imperial, on: .monday, sessionID: session.serverID, exerciseID: UUID()))
        XCTAssertEqual(session, original)
    }

    func testAccountDefaultIsOnlyAFallbackForAnUnselectedLegacyRow() {
        let session = session()
        XCTAssertNil(session.exercises[0].displayUnit)
        XCTAssertEqual(session.exercises[0].weightUnit(default: .imperial), .imperial)
        XCTAssertEqual(session.exercises[0].weightUnit(default: .metric), .metric)
    }

    func testLoadedDefaultIsAdoptedWithoutOverwritingExistingChoices() {
        var session = session()
        change(&session, row: 0, to: .metric)
        XCTAssertTrue(session.adoptDefaultDisplayUnits(.imperial))
        XCTAssertEqual(session.exercises.map(\.displayUnit), [.metric, .imperial])
        XCTAssertFalse(session.adoptDefaultDisplayUnits(.metric))
        XCTAssertEqual(session.exercises.map(\.displayUnit), [.metric, .imperial])
    }

    func testMixedUnitsRoundTripThroughTheLocalCheckpoint() throws {
        var original = session()
        change(&original, row: 0, to: .imperial)
        change(&original, row: 1, to: .metric)
        let restored = try JSONDecoder().decode(ActiveWorkoutSession.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.exercises.map(\.displayUnit), [.imperial, .metric])
    }

    func testOlderCheckpointWithoutUnitsStillRestoresAllWorkoutData() throws {
        let original = session()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["exercises"] = try XCTUnwrap(object["exercises"] as? [[String: Any]]).map { row in
            var row = row
            row.removeValue(forKey: "displayUnit")
            return row
        }
        var restored = try JSONDecoder().decode(ActiveWorkoutSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored, original)
        XCTAssertTrue(restored.exercises.allSatisfy { $0.displayUnit == nil })
        restored.adoptDefaultDisplayUnits(.imperial)
        XCTAssertEqual(restored.exercises.map(\.displayUnit), [.imperial, .imperial])
        XCTAssertEqual(restored.exercises.map(\.sets), original.exercises.map(\.sets))
    }

    func testUnknownFutureCheckpointUnitDoesNotLoseTheSession() throws {
        let original = session()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var rows = try XCTUnwrap(object["exercises"] as? [[String: Any]])
        rows[0]["displayUnit"] = "future-unit"
        object["exercises"] = rows
        let restored = try JSONDecoder().decode(ActiveWorkoutSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.exercises[0].displayUnit)
        XCTAssertEqual(restored.exercises[0].weightUnit(default: .imperial), .imperial)
        XCTAssertEqual(restored.exercises.map(\.sets), original.exercises.map(\.sets))
    }

    func testReorderingKeepsEachChoiceWithItsExerciseIdentity() {
        var session = session()
        change(&session, row: 0, to: .imperial)
        change(&session, row: 1, to: .metric)
        let first = session.exercises[0], second = session.exercises[1]
        session.exercises.swapAt(0, 1)
        XCTAssertEqual(session.exercises, [second, first])
        XCTAssertEqual(session.exercises[0].displayUnit, .metric)
        XCTAssertEqual(session.exercises[1].displayUnit, .imperial)
    }

    func testSetResponseAndRecoveryMutationsKeepTheCurrentUnit() throws {
        var saved = session()
        change(&saved, row: 0, to: .imperial)
        var restored = try JSONDecoder().decode(ActiveWorkoutSession.self, from: JSONEncoder().encode(saved))
        // These are the fields logSet/reconcileLoggedSets replace with the
        // server response. The current exercise itself is never reconstructed.
        restored.exercises[0].sets[1].serverID = 1001
        restored.exercises[0].sets[1].weightKilograms = "61.23"
        restored.exercises[0].sets[1].reps = "8"
        restored.exercises[0].sets[1].isLogged = true
        XCTAssertEqual(restored.exercises[0].displayUnit, .imperial)
        XCTAssertEqual(restored.exercises[0].weightUnit(default: .metric)
            .display(kilograms: restored.exercises[0].sets[1].weightKilograms), "135")
        XCTAssertEqual(restored.exercises[1], saved.exercises[1])
    }

    func testStartingAnotherSessionDoesNotInheritPreviousChoices() {
        var previous = session()
        change(&previous, row: 0, to: .imperial)
        var next = session(serverID: 4343)
        XCTAssertTrue(next.exercises.allSatisfy { $0.displayUnit == nil })
        next.adoptDefaultDisplayUnits(.metric)
        XCTAssertEqual(next.exercises.map(\.displayUnit), [.metric, .metric])
        XCTAssertFalse(next.setExerciseDisplayUnit(.imperial, on: next.day,
                                                  sessionID: previous.serverID, exerciseID: previous.exercises[0].id))
    }

    func testNewlyAddedExerciseTakesItsOwnDefaultNotItsNeighborsChoice() {
        var session = session()
        change(&session, row: 0, to: .imperial)
        let added = SessionExerciseDraft(id: UUID(), exerciseServerID: 12, sessionExerciseID: 103,
                                        name: "Row", sets: [WorkoutSetDraft(setNumber: 1)])
        session.exercises.append(added)
        session.adoptDefaultDisplayUnits(.metric)
        XCTAssertEqual(session.exercises.map(\.displayUnit), [.imperial, .metric, .metric])
    }

    func testTargetsAndPreviousWeightsUseTheSameSelectedExerciseUnit() {
        var session = session()
        change(&session, row: 0, to: .imperial)
        let first = session.exercises[0], second = session.exercises[1]
        let unit = first.weightUnit(default: .metric)
        XCTAssertEqual(unit.display(kilograms: first.targetWeightKilograms!), "132.3")
        XCTAssertEqual(unit.display(kilograms: first.sets[0].weightKilograms), "132.3")
        XCTAssertEqual(second.weightUnit(default: .metric).display(kilograms: second.sets[0].weightKilograms), "60")
    }

    private func source(_ path: String) throws -> String {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        return try String(contentsOf: URL(fileURLWithPath: root)
            .appendingPathComponent("IOS Frontend/IOS Frontend/\(path)"), encoding: .utf8)
    }

    // Wiring guards complement model tests; they are not device/widget tests.
    func testStoreSetterIsLocalAndUsesTheTestedIdentityGuard() throws {
        let store = try source("Stores/WorkoutStore.swift")
        let begin = try XCTUnwrap(store.range(of: "func setSessionExerciseDisplayUnit("))
        let end = try XCTUnwrap(store.range(of: "private func withInitialDisplayUnits(", range: begin.upperBound..<store.endIndex))
        let setter = String(store[begin.lowerBound..<end.lowerBound])
        XCTAssertTrue(setter.contains("guard !isSaving, !isRecoveringWorkouts"))
        XCTAssertTrue(setter.contains("session.setExerciseDisplayUnit(unit, on: day, sessionID: sessionID, exerciseID: exerciseID)"))
        XCTAssertTrue(setter.contains("activeSession = session"))
        XCTAssertFalse(setter.contains("repository"))
        XCTAssertFalse(setter.contains("makeDefault"))
        XCTAssertFalse(setter.contains("useTemporarily"))
        XCTAssertTrue(store.contains("let session = withInitialDisplayUnits(opened)"))
        XCTAssertTrue(store.contains("activeSession = withInitialDisplayUnits(reconciled)"))
        XCTAssertTrue(store.contains("displayUnit: preferences.hasLoadedUnit ? preferences.defaultWeightUnit : nil"))
        XCTAssertTrue(store.contains("if preferences.hasLoadedUnit"))
    }

    func testServerReconciliationPreservesCheckpointMetadataAndLiveActivityUsesFocusedUnit() throws {
        let repository = try source("API/WorkoutAPIRepository.swift")
        let begin = try XCTUnwrap(repository.range(of: "func reconcileLoggedSets("))
        let end = try XCTUnwrap(repository.range(of: "return session", range: begin.upperBound..<repository.endIndex))
        let reconcile = String(repository[begin.lowerBound..<end.upperBound])
        XCTAssertTrue(reconcile.contains("var session = saved"))
        XCTAssertFalse(reconcile.contains("SessionExerciseDraft("))
        XCTAssertFalse(reconcile.contains("displayUnit ="))
        let activity = try source("LiveActivity/WorkoutLiveActivityController.swift")
        XCTAssertTrue(activity.contains("let exerciseUnit = exercise?.weightUnit(default: unit) ?? unit"))
        XCTAssertTrue(activity.contains("exerciseUnit.formatted(kilograms: weight)"))
        XCTAssertTrue(activity.contains("previousText: hint?.summary(in: exerciseUnit)"))
    }
}
