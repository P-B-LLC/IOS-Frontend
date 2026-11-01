import Foundation
import XCTest
@testable import AccountSafety

final class RotationWorkoutSelectionTests: XCTestCase {
    func testTheSameSavedTemplateCanFillSeveralRotationDays() {
        var draft = WorkoutCycleDraft()
        XCTAssertTrue(draft.selectSavedWorkout(id: 12, name: "Push Day", at: 1))
        XCTAssertTrue(draft.selectSavedWorkout(id: 12, name: "Push Day", at: 4))

        XCTAssertEqual(draft.slots.map(\.workoutID), [12, nil, nil, 12, nil, nil, nil, nil])
        XCTAssertEqual(draft.slots[0].workoutName, "Push Day")
        XCTAssertEqual(draft.slots[3].workoutName, "Push Day")
        XCTAssertTrue(draft.hasAnyWorkout)
    }

    func testSelectedIdentityWinsEvenWhenAnotherWorkoutHasTheSameDisplayName() {
        var draft = WorkoutCycleDraft()
        draft.slots[0].serverID = 81
        XCTAssertTrue(draft.selectSavedWorkout(id: 12, name: "Push Day", at: 1))
        XCTAssertTrue(draft.selectSavedWorkout(id: 91, name: "Push Day", at: 2))
        let secondSlot = draft.slots[1]

        XCTAssertTrue(draft.selectSavedWorkout(id: 91, name: "Push Day", at: 1))
        XCTAssertEqual(draft.slots[0].workoutID, 91)
        XCTAssertEqual(draft.slots[0].serverID, 81, "The rotation slot keeps its own server identity")
        XCTAssertEqual(draft.slots[1], secondSlot, "Replacing one day must leave other days intact")
    }

    func testAStaleDayCannotAddOrReplaceAnotherSlot() {
        var draft = WorkoutCycleDraft()
        XCTAssertTrue(draft.selectSavedWorkout(id: 12, name: "Push Day", at: 1))
        draft.resize(to: 3)
        let before = draft

        XCTAssertFalse(draft.selectSavedWorkout(id: 91, name: "Leg Day", at: 4))
        XCTAssertFalse(draft.selectSavedWorkout(id: 91, name: "Leg Day", at: 0))
        XCTAssertEqual(draft, before)
    }

    func testSavedSelectionDoesNotEnterTheCreateOrSchedulePaths() throws {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        let source = try String(contentsOf: URL(fileURLWithPath: root)
            .appendingPathComponent("IOS Frontend/IOS Frontend/Views/Workouts/CycleEditorView.swift"), encoding: .utf8)
        let beginning = try XCTUnwrap(source.range(of: "onChoose: { selected in"))
        let ending = try XCTUnwrap(source.range(of: "onCreate:", range: beginning.upperBound..<source.endIndex))
        let choosing = String(source[beginning.lowerBound..<ending.lowerBound])
        XCTAssertTrue(choosing.contains("id: selected.serverID"))
        XCTAssertFalse(choosing.contains("createTemplate"))
        XCTAssertFalse(choosing.contains("schedule"))
        XCTAssertFalse(choosing.contains("update"))
        XCTAssertTrue(source.contains("if createdWorkout { dismiss() }"))
        XCTAssertTrue(source.contains("recoveryContext: \"rotation-"))
    }
}
