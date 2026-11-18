import Foundation
import RepbaseAPI
import XCTest
@testable import AccountSafety

final class WorkoutPlannedSetTests: XCTestCase {
    private func targets() -> [WorkoutPlannedSet] {
        [WorkoutPlannedSet(setType: .warmup, targetReps: 12, targetWeightKilograms: "20"),
         WorkoutPlannedSet(targetReps: 10, targetWeightKilograms: "50"),
         WorkoutPlannedSet(targetReps: 8, targetWeightKilograms: "60")]
    }

    private func exercise(_ plan: [WorkoutPlannedSet]? = nil) -> SessionExerciseDraft {
        let plan = plan ?? targets()
        return SessionExerciseDraft(id: UUID(), exerciseServerID: 3, sessionExerciseID: 8,
                                    name: "Bench Press",
                                    sets: plan.enumerated().map {
                                        WorkoutSetDraft(setNumber: $0.offset + 1, setType: $0.element.setType,
                                                        plannedSetID: $0.element.id)
                                    }, workoutExerciseID: 4, targetReps: 99,
                                    targetWeightKilograms: "999", plannedSets: plan)
    }

    private func session(_ row: SessionExerciseDraft) -> ActiveWorkoutSession {
        var session = ActiveWorkoutSession(id: UUID(), serverID: 1, day: .monday,
                                           workoutID: UUID(), workoutServerID: 2, workoutName: "Push",
                                           workoutType: .lifting, startedAt: Date(timeIntervalSince1970: 1),
                                           exercises: [row])
        session.plan = session.structure
        return session
    }

    func testLegacyMaterializationKeepsWarmupBlankAndWorkingTargets() {
        var row = Exercise(name: "Press", sets: 3, setTypes: [.warmup], targetReps: 8, targetWeightKilograms: "60")
        let first = row.effectivePlannedSets
        XCTAssertEqual(first, row.effectivePlannedSets)
        row.materializePlannedSets()
        XCTAssertEqual(row.plannedSets, first)
        XCTAssertEqual(row.plannedSets.map(\.targetReps), [nil, 8, 8])
        XCTAssertEqual(row.plannedSets.map(\.targetWeightKilograms), [nil, "60", "60"])
        XCTAssertNil(row.targetReps, "Explicit plans must not leave a misleading shared target for old readers")
        XCTAssertNil(row.targetWeightKilograms)
    }

    func testLegacyIDsDoNotCollideBetweenServerDerivedExerciseRows() {
        let a = Exercise(id: .stable(forServerID: 1), name: "Press", sets: 3)
        let b = Exercise(id: .stable(forServerID: 2), name: "Press", sets: 3)
        XCTAssertTrue(Set(a.effectivePlannedSets.map(\.id)).isDisjoint(with: b.effectivePlannedSets.map(\.id)))
    }

    func testLegacyZeroRepsMeansUnspecifiedNotAnInvalidNewTarget() {
        var legacy = Exercise(name: "Press", sets: 2, targetReps: 0, targetWeightKilograms: "0")
        legacy.materializePlannedSets()
        XCTAssertTrue(legacy.plannedSets.allSatisfy { $0.targetReps == nil })
        XCTAssertEqual(legacy.plannedSets.map(\.targetWeightKilograms), ["0", "0"])
        XCTAssertTrue(WorkoutPlannedSetPolicy.isValid(legacy.plannedSets))
        var row = exercise()
        row.plannedSets = nil
        row.targetReps = 0
        row.sets[1].reps = "0"
        XCTAssertNil(row.targetReps(for: row.sets[1]))
        XCTAssertEqual(row.sets[1].reps, "0", "Actual logged zero reps are not a planned target")
    }

    func testServerSnapshotBuildsExactRowsIndependentlyOfStaleLocalPlan() {
        let serverPlan = targets()
        let row = SessionExerciseDraft.fromPlanSnapshot(
            sessionExerciseID: 91, exerciseServerID: 3, name: "Press", workoutExerciseID: 12,
            restSeconds: 90, supersetGroup: 2, plannedSets: serverPlan
        )
        XCTAssertEqual(row.id, .stable(forServerID: 91))
        XCTAssertEqual(row.workoutExerciseID, 12)
        XCTAssertEqual(row.plannedSets, serverPlan)
        XCTAssertEqual(row.sets.map(\.plannedSetID), serverPlan.map { Optional($0.id) })
        XCTAssertEqual(row.sets.map { row.targetReps(for: $0) }, [12, 10, 8])
        XCTAssertTrue(row.sets.allSatisfy { $0.reps.isEmpty && $0.weightKilograms.isEmpty && !$0.isLogged })
    }

    func testRepeatedCatalogMovementsWithCopiedPlanIDsStayIndependent() {
        let copiedRows = targets()
        let a = SessionExerciseDraft.fromPlanSnapshot(
            sessionExerciseID: 91, exerciseServerID: 3, name: "Press", workoutExerciseID: 12,
            restSeconds: nil, supersetGroup: nil, plannedSets: copiedRows
        )
        var b = SessionExerciseDraft.fromPlanSnapshot(
            sessionExerciseID: 92, exerciseServerID: 3, name: "Press", workoutExerciseID: 13,
            restSeconds: nil, supersetGroup: nil, plannedSets: copiedRows
        )
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertTrue(Set(a.sets.map(\.id)).isDisjoint(with: b.sets.map(\.id)))
        b.sets[1].reps = "5"
        b.displayUnit = .imperial
        XCTAssertEqual(a.sets[1].reps, "")
        XCTAssertNil(a.displayUnit)
        XCTAssertEqual(a.targetReps(for: a.sets[1]), 10)
    }

    func testResizeRetainsIdentityAndTargetsAndAddsBlankRows() {
        let plan = targets()
        var row = Exercise(name: "Press", plannedSets: plan)
        row.resizePlannedSets(to: 4)
        XCTAssertEqual(Array(row.plannedSets.prefix(3)), plan)
        XCTAssertNil(row.plannedSets[3].targetReps)
        XCTAssertNil(row.plannedSets[3].targetWeightKilograms)
        row.sets = 2
        XCTAssertEqual(row.plannedSets, Array(plan.prefix(2)))
        XCTAssertEqual(row.targetSets, 2)
        XCTAssertEqual(row.plannedSetTypes, [.warmup, .normal])
    }

    func testReorderAndKindChangesKeepTargetsAttachedToRowIDs() {
        let plan = targets()
        var row = Exercise(name: "Press", plannedSets: plan)
        row.replacePlannedSets([plan[2], plan[0], plan[1]])
        row.setType(.drop, at: 0)
        XCTAssertEqual(row.plannedSets.map(\.id), [plan[2].id, plan[0].id, plan[1].id])
        XCTAssertEqual(row.plannedSets.map(\.targetReps), [8, 12, 10])
        XCTAssertEqual(row.plannedSets[0].targetWeightKilograms, "60")
        XCTAssertEqual(row.plannedSetTypes, [.drop, .warmup, .normal])
    }

    func testPerSetTargetsOverrideSharedTargetsIncludingExplicitWarmup() {
        let row = exercise()
        XCTAssertEqual(row.sets.map { row.targetReps(for: $0) }, [12, 10, 8])
        XCTAssertEqual(row.sets.map { row.targetWeightKilograms(for: $0) }, ["20", "50", "60"])
    }

    func testExplicitBlankTargetNeverFallsBackToGenericExerciseTarget() {
        let row = exercise([WorkoutPlannedSet()])
        XCTAssertNil(row.targetReps(for: row.sets[0]))
        XCTAssertNil(row.targetWeightKilograms(for: row.sets[0]))
    }

    func testRemovingMiddleSetDoesNotShiftRemainingTarget() {
        var row = exercise()
        let last = row.sets[2]
        row.sets.remove(at: 1)
        XCTAssertEqual(row.targetReps(for: last), 8)
        XCTAssertEqual(row.targetWeightKilograms(for: last), "60")
        XCTAssertEqual(row.reusablePlannedSets.map(\.targetReps), [12, 8])
    }

    func testSetReorderUsesSourceIdentityNotVisibleIndex() {
        var row = exercise()
        row.sets.swapAt(0, 2)
        XCTAssertEqual(row.sets.map { row.targetWeightKilograms(for: $0) }, ["60", "50", "20"])
    }

    func testActualPerformanceCannotPromoteItselfIntoReusableTargets() {
        var row = exercise()
        let plan = row.reusablePlannedSets
        row.sets[0].weightKilograms = "80"
        row.sets[0].reps = "3"
        row.sets[0].isLogged = true
        XCTAssertEqual(row.reusablePlannedSets, plan)
        var workout = session(row)
        workout.exercises[0].sets[1].weightKilograms = "100"
        workout.exercises[0].sets[1].reps = "1"
        XCTAssertTrue(workout.structureChanges.isEmpty)
    }

    func testAddedSetHasStableBlankTargetAndDoesNotBorrowPreviousPerformance() {
        var row = exercise()
        let added = WorkoutSetDraft(setNumber: 4, weightKilograms: "70", reps: "5", isLogged: true)
        row.sets.append(added)
        let target = row.reusablePlannedSets.last!
        XCTAssertEqual(target.id, added.id)
        XCTAssertNil(target.targetReps)
        XCTAssertNil(target.targetWeightKilograms)
        XCTAssertEqual(row.reusablePlannedSets.last, target)
    }

    func testKnownEmptySnapshotNeverUsesLegacySharedTargets() {
        var row = exercise()
        row.plannedSets = []
        XCTAssertNil(row.targetReps(for: row.sets[1]))
        XCTAssertNil(row.targetWeightKilograms(for: row.sets[1]))
    }

    func testLegacyCheckpointStillUsesSharedTargetsButNotForWarmups() {
        var row = exercise()
        row.plannedSets = nil
        XCTAssertNil(row.targetReps(for: row.sets[0]))
        XCTAssertEqual(row.targetReps(for: row.sets[1]), 99)
    }

    func testCheckpointRoundTripPreservesIDsTargetsAndIndependentDisplayUnit() throws {
        var row = exercise()
        row.displayUnit = .imperial
        let source = session(row)
        let restored = try JSONDecoder().decode(ActiveWorkoutSession.self, from: JSONEncoder().encode(source))
        XCTAssertEqual(restored, source)
        XCTAssertEqual(restored.exercises[0].displayUnit, .imperial)
        XCTAssertEqual(restored.exercises[0].targetWeightKilograms(for: restored.exercises[0].sets[2]), "60")
    }

    func testOldCheckpointMissingAllPlanningFieldsDecodes() throws {
        let original = exercise()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "plannedSets")
        var sets = try XCTUnwrap(json["sets"] as? [[String: Any]])
        for index in sets.indices { sets[index].removeValue(forKey: "plannedSetID") }
        json["sets"] = sets
        let restored = try JSONDecoder().decode(SessionExerciseDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.plannedSets)
        XCTAssertTrue(restored.sets.allSatisfy { $0.plannedSetID == nil })
    }

    func testServerSnapshotAdoptionUsesSetNumberGapsAndRunsOnlyOnce() {
        let plan = targets()
        var row = SessionExerciseDraft(id: UUID(), exerciseServerID: 3, sessionExerciseID: 8, name: "Press",
                                       sets: [WorkoutSetDraft(setNumber: 1), WorkoutSetDraft(setNumber: 3)])
        row.adoptPlanSnapshot(plan)
        XCTAssertEqual(row.sets.map(\.plannedSetID), [plan[0].id, plan[2].id])
        XCTAssertEqual(row.targetReps(for: row.sets[1]), 8)
        row.adoptPlanSnapshot([WorkoutPlannedSet(targetReps: 1)])
        XCTAssertEqual(row.plannedSets, plan)
    }

    func testPlanTargetChangeParticipatesInExplicitSaveForNextTimeDiff() {
        var workout = session(exercise())
        workout.exercises[0].plannedSets?[1].targetReps = 6
        XCTAssertEqual(workout.structureChanges, [.targets("Bench Press")])
    }

    func testValidationRejectsMalformedWeightsAndBoundaryReps() {
        for weight in ["", "-1", "100000", "1.234", "12junk", "NaN", "1e3", "1,000"] {
            XCTAssertFalse(WorkoutPlannedSetPolicy.isValid([WorkoutPlannedSet(targetWeightKilograms: weight)]), weight)
        }
        for reps in [0, -1, 1001] {
            XCTAssertFalse(WorkoutPlannedSetPolicy.isValid([WorkoutPlannedSet(targetReps: reps)]))
        }
        XCTAssertTrue(WorkoutPlannedSetPolicy.isValid([WorkoutPlannedSet(targetReps: 1000, targetWeightKilograms: "99999.99")]))
        XCTAssertTrue(WorkoutPlannedSetPolicy.isValid([WorkoutPlannedSet(targetWeightKilograms: "0")]))
        XCTAssertTrue(WorkoutPlannedSetPolicy.isValid([WorkoutPlannedSet()]))
    }

    func testDuplicateRowsAndOverLimitPlansCannotBeSaved() {
        let row = WorkoutPlannedSet()
        XCTAssertFalse(WorkoutPlannedSetPolicy.isValid([row, row]))
        XCTAssertFalse(WorkoutPlannedSetPolicy.isValid((0..<51).map { _ in WorkoutPlannedSet() }))
    }

    func testCanonicalReadbackComparisonHandlesFixedDecimalPrecision() {
        var a = targets(), b = a
        a[1].targetWeightKilograms = "50"
        b[1].targetWeightKilograms = "50.00"
        XCTAssertTrue(WorkoutPlannedSetPolicy.sameTargets(a, b))
        b[1].targetWeightKilograms = "50.01"
        XCTAssertFalse(WorkoutPlannedSetPolicy.sameTargets(a, b))
    }

    func testPoundsEntryConvertsOnceAndLeavesCanonicalPlanUnchangedOnDisplay() {
        let canonical = WorkoutWeightUnit.imperial.kilograms(display: "135")
        XCTAssertEqual(canonical, "61.23")
        let row = WorkoutPlannedSet(targetWeightKilograms: canonical)
        XCTAssertTrue(WorkoutPlannedSetPolicy.isValid([row]))
        for _ in 0..<50 {
            _ = WorkoutWeightUnit.metric.display(kilograms: canonical)
            _ = WorkoutWeightUnit.imperial.display(kilograms: canonical)
        }
        XCTAssertEqual(row.targetWeightKilograms, "61.23")
    }

    func testGeneratedCreatePayloadCarriesOrderedTargetsAndVersionWithoutActualLogs() throws {
        let ids = [UUID().uuidString.lowercased(), UUID().uuidString.lowercased()]
        let rows: [Components.Schemas.WorkoutPlannedSetRequest] = [
            .init(id: ids[0], setType: .warmup, targetReps: 12, targetWeightKg: "20"),
            .init(id: ids[1], setType: .normal, targetReps: 8, targetWeightKg: "60")
        ]
        let initial = WorkoutTemplateCreation.initialExercises([
            .init(exerciseID: 3, targetSets: 2, plannedSets: rows)
        ])
        let request = Components.Schemas.WorkoutTemplateRequest(name: "Push", initialExercises: initial, plannedSetsVersion: 1)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(json["planned_sets_version"] as? Int, 1)
        let exercises = try XCTUnwrap(json["initial_exercises"] as? [[String: Any]])
        let sets = try XCTUnwrap(exercises.first?["planned_sets"] as? [[String: Any]])
        XCTAssertEqual(sets.compactMap { $0["id"] as? String }, ids)
        XCTAssertEqual(sets.compactMap { $0["target_reps"] as? Int }, [12, 8])
        XCTAssertNil(sets[0]["weight_kg"])
        XCTAssertNil(sets[0]["is_logged"])
        XCTAssertNil(json["owner"])
    }

    func testGeneratedSessionResponseKeepsNullableLegacyAndExplicitSnapshotDistinct() throws {
        let base = #"{"id":8,"session":1,"exercise":3,"exercise_name":"Press"}"#
        let legacy = try JSONDecoder().decode(Components.Schemas.SessionExercise.self, from: Data(base.utf8))
        XCTAssertNil(legacy.plannedSets)
        let explicit = #"{"id":8,"session":1,"exercise":3,"exercise_name":"Press","planned_sets":[],"workout_exercise_id":4}"#
        let row = try JSONDecoder().decode(Components.Schemas.SessionExercise.self, from: Data(explicit.utf8))
        XCTAssertEqual(row.plannedSets?.count, 0)
        XCTAssertEqual(row.workoutExerciseId, 4)
    }

    func testRepositoryGuardsBeforeWritesAndConfirmsReadback() throws {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        let url = URL(fileURLWithPath: root).appendingPathComponent("IOS Frontend/IOS Frontend/API/WorkoutAPIRepository.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let begin = try XCTUnwrap(source.range(of: "func createTemplate(_ draft:"))
        let end = try XCTUnwrap(source.range(of: "func acknowledgeTemplateSave", range: begin.upperBound..<source.endIndex))
        let create = String(source[begin.lowerBound..<end.lowerBound])
        let probe = try XCTUnwrap(create.range(of: "try await requirePlannedSetSupport()"))
        let resolve = try XCTUnwrap(create.range(of: "resolveExercise("))
        XCTAssertLessThan(probe.lowerBound, resolve.lowerBound)
        XCTAssertTrue(create.contains("try await confirmPlan(draft.exercises, templateID: template.id)"))
        XCTAssertTrue(source.contains("relation.workoutExerciseId"))
        XCTAssertTrue(source.contains("sessionRelations.allSatisfy({ $0.plannedSets != nil })"))
        XCTAssertTrue(source.contains("session.exercises[index].adoptPlanSnapshot(snapshot)"))
        XCTAssertTrue(source.contains("SessionExerciseDraft.fromPlanSnapshot("))
        XCTAssertTrue(source.contains("let serverFamily = started.workoutType"))
        XCTAssertTrue(source.contains("template.id == templateID"))
    }
}
