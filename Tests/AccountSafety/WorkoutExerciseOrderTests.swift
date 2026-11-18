import Foundation
import RepbaseAPI
import XCTest
@testable import AccountSafety

final class WorkoutExerciseOrderTests: XCTestCase {
    private func exercise(_ number: Int, catalogID: Int? = nil) -> Exercise {
        Exercise(
            serverID: catalogID ?? number, workoutExerciseID: 1_000 + number,
            serverName: "Catalog \(number)", name: "Exercise \(number)", sets: 4,
            setTypes: [.warmup, .normal, .drop, .failure], restSeconds: 30 + number,
            supersetGroup: number % 2, targetReps: 5 + number,
            targetWeightKilograms: "\(number).125"
        )
    }

    func testMovesLastCardToFirstWithoutRebuildingAnyExercise() {
        let original = [exercise(1), exercise(2), exercise(3)]
        let moved = WorkoutExerciseOrder.moving(original, fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(moved, [original[2], original[0], original[1]])
        XCTAssertEqual(moved[0].workoutExerciseID, 1_003)
        XCTAssertEqual(moved[0].targetWeightKilograms, "3.125")
        XCTAssertEqual(moved[0].setTypes, [.warmup, .normal, .drop, .failure])
        XCTAssertEqual(moved[0].supersetGroup, 1)
    }

    func testMovesFirstCardToEndUsingTheNativeInsertionOffset() {
        let original = [exercise(1), exercise(2), exercise(3)]
        XCTAssertEqual(WorkoutExerciseOrder.moving(original, fromOffsets: [0], toOffset: 3),
                       [original[1], original[2], original[0]])
    }

    func testFlyCanMoveBeforeTricepsInATwelveExercisePlan() {
        let original = (1...12).map { exercise($0) }
        let moved = WorkoutExerciseOrder.moving(original, fromOffsets: [11], toOffset: 9)
        XCTAssertEqual(moved.map(\.id), Array(original[..<9]).map(\.id) +
                       [original[11].id, original[9].id, original[10].id])
        XCTAssertEqual(Set(moved.map(\.id)), Set(original.map(\.id)))
        XCTAssertEqual(moved.count, 12)
    }

    func testMultipleMovedRowsKeepTheirRelativeOrderAndDetails() {
        let original = (1...4).map { exercise($0) }
        XCTAssertEqual(WorkoutExerciseOrder.moving(original, fromOffsets: [0, 2], toOffset: 4),
                       [original[1], original[3], original[0], original[2]])
    }

    func testInvalidOffsetsAndNoOpDropsLeaveTheDraftUnchanged() {
        let original = [exercise(1), exercise(2)]
        let cases: [(IndexSet, Int)] = [([], 0), ([99], 0), ([0, 99], 1),
                                      ([0], -1), ([0], 3), ([0], 0), ([0], 1)]
        for (source, destination) in cases {
            XCTAssertEqual(WorkoutExerciseOrder.moving(original, fromOffsets: source, toOffset: destination), original)
        }
        XCTAssertEqual(WorkoutExerciseOrder.moving([], fromOffsets: [0], toOffset: 0), [])
        XCTAssertEqual(WorkoutExerciseOrder.moving([original[0]], fromOffsets: [0], toOffset: 1), [original[0]])
    }

    func testAccessibleMoveUsesTheSameOrderAndBoundsAsDragging() {
        let original = [exercise(1), exercise(2), exercise(3)]
        XCTAssertEqual(WorkoutExerciseOrder.moving(original[2].id, by: -1, in: original),
                       WorkoutExerciseOrder.moving(original, fromOffsets: [2], toOffset: 1))
        XCTAssertEqual(WorkoutExerciseOrder.moving(original[0].id, by: 1, in: original),
                       WorkoutExerciseOrder.moving(original, fromOffsets: [0], toOffset: 2))
        XCTAssertEqual(WorkoutExerciseOrder.moving(original[0].id, by: -1, in: original), original)
        XCTAssertEqual(WorkoutExerciseOrder.moving(original[2].id, by: 1, in: original), original)
        XCTAssertEqual(WorkoutExerciseOrder.moving(UUID(), by: 1, in: original), original)
        XCTAssertEqual(WorkoutExerciseOrder.moving(original[2].id, by: Int.max, in: original), original)
    }

    func testRepeatedCatalogIDsStillMoveAsDistinctPlannedRows() {
        let original = [exercise(1, catalogID: 53), exercise(2, catalogID: 21), exercise(3, catalogID: 53)]
        let moved = WorkoutExerciseOrder.moving(original[2].id, by: -2, in: original)
        XCTAssertEqual(moved, [original[2], original[0], original[1]])
        XCTAssertEqual(moved.map(\.serverID), [53, 53, 21])
        XCTAssertEqual(moved.map(\.workoutExerciseID), [1_003, 1_001, 1_002])
        XCTAssertEqual(Set(moved.map(\.id)).count, 3)
    }

    func testDraftRecoveryRetainsReorderedRowsAndAllPlanningMetadata() throws {
        let original = [exercise(1), exercise(2), exercise(3)]
        var draft = Workout(name: "My ordered workout", exercises: original)
        draft.exercises = WorkoutExerciseOrder.moving(original, fromOffsets: [2], toOffset: 0)
        let restored = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft)
        XCTAssertEqual(restored.exercises, [original[2], original[0], original[1]])
    }

    func testCreatePayloadUsesTheReorderedPlanAndSequentialPositions() throws {
        let original = [exercise(1), exercise(2), exercise(3)]
        let moved = WorkoutExerciseOrder.moving(original, fromOffsets: [2], toOffset: 0)
        let selections = try moved.map { value in
            WorkoutTemplateCreation.Selection(
                exerciseID: try XCTUnwrap(value.serverID), targetSets: value.targetSets,
                targetReps: value.targetReps, targetWeightKilograms: value.targetWeightKilograms,
                restSeconds: value.restSeconds, supersetGroup: value.supersetGroup
            )
        }
        let payload = WorkoutTemplateCreation.initialExercises(selections)
        XCTAssertEqual(payload.map(\.exercise), [3, 1, 2])
        XCTAssertEqual(payload.map(\.order), [1, 2, 3])
        XCTAssertEqual(payload.map(\.targetReps), [8, 6, 7])
        XCTAssertEqual(payload.map(\.targetWeightKg), ["3.125", "1.125", "2.125"])
        XCTAssertEqual(payload.map(\.restSeconds), [33, 31, 32])
    }

    func testStartingTheSavedPlanResolvesSessionRowsInItsReorderedOrder() throws {
        let original = [exercise(1, catalogID: 53), exercise(2, catalogID: 21), exercise(3, catalogID: 53)]
        let moved = WorkoutExerciseOrder.moving(original, fromOffsets: [2], toOffset: 0)
        let serverRows = [21, 53, 53]
        let indices = try XCTUnwrap(WorkoutSelectionPolicy.sessionRelationIndices(
            planned: moved.map(\.serverID), actual: serverRows
        ))
        XCTAssertEqual(indices, [1, 2, 0])
        XCTAssertEqual(indices.map { serverRows[$0] }, moved.compactMap(\.serverID))
    }

    // Wiring guards supplement, rather than claim to replace, native drag QA.
    func testBuilderUsesInlineNativeReorderingAndNoSeparateDraftSheet() throws {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        let path = URL(fileURLWithPath: root)
            .appendingPathComponent("IOS Frontend/IOS Frontend/Views/Workouts/GuidedWorkoutBuilder.swift")
        let builder = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(builder.contains(".onMove(perform: moveExercises)"))
        XCTAssertTrue(builder.contains("WorkoutExerciseOrder.moving(draft.exercises"))
        XCTAssertTrue(builder.contains("Button { stage = .exercises } label:"))
        XCTAssertTrue(builder.contains("Text(\"Edit exercise order\")"))
        XCTAssertTrue(builder.contains(".task(id: orderFeedbackID)"))
        XCTAssertTrue(builder.contains(".accessibilityActions"))
        XCTAssertFalse(builder.contains("DraftReorderSheet"))
        XCTAssertFalse(builder.contains(".onDrag"))
        XCTAssertFalse(builder.contains(".onDrop"))
        XCTAssertFalse(builder.contains(".constant(.active)"))
    }
}
