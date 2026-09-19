import XCTest
@testable import AccountSafety

final class WorkoutWidgetControlsTests: XCTestCase {
    func testAdvancesSetsBeforeMovingToNextExercise() {
        XCTAssertEqual(WorkoutWidgetControls.nextSet(in: [[true, false], [false]]), .init(exercise: 0, set: 1))
        XCTAssertEqual(WorkoutWidgetControls.nextSet(in: [[true, true], [false]]), .init(exercise: 1, set: 0))
        XCTAssertNil(WorkoutWidgetControls.nextSet(in: [[true, true], [true]]))
    }
    func testFailedSaveDoesNotAdvanceAndEmptyExercisesAreSkipped() {
        let pending = [[], [true, false], [false]]
        XCTAssertEqual(WorkoutWidgetControls.nextSet(in: pending), .init(exercise: 1, set: 1))
        XCTAssertEqual(WorkoutWidgetControls.nextSet(in: pending), .init(exercise: 1, set: 1))
        XCTAssertNil(WorkoutWidgetControls.nextSet(in: []))
        XCTAssertNil(WorkoutWidgetControls.nextSet(in: [[], []]))
    }
    func testExactDecimalWeightStepsAndInvalidDrafts() {
        XCTAssertEqual(WorkoutWidgetControls.weight("60", increasing: true), "62.5")
        XCTAssertEqual(WorkoutWidgetControls.weight("62.5", increasing: false), "60")
        XCTAssertEqual(WorkoutWidgetControls.weight("0.1", increasing: true), "2.6")
        XCTAssertEqual(WorkoutWidgetControls.weight("", increasing: true), "2.5")
        XCTAssertEqual(WorkoutWidgetControls.weight("-10", increasing: true), "-7.5")
        XCTAssertEqual(WorkoutWidgetControls.weight("99999", increasing: true), "99999")
        XCTAssertNil(WorkoutWidgetControls.weight("NaN", increasing: true))
        XCTAssertNil(WorkoutWidgetControls.weight("1,5", increasing: true))
        XCTAssertNil(WorkoutWidgetControls.weight("invalid", increasing: true))
    }
    func testRepLimitsAndInvalidInput() {
        XCTAssertEqual(WorkoutWidgetControls.reps("", increasing: true), "1")
        XCTAssertEqual(WorkoutWidgetControls.reps("0", increasing: false), "0")
        XCTAssertEqual(WorkoutWidgetControls.reps("999", increasing: true), "999")
        XCTAssertEqual(WorkoutWidgetControls.reps("8", increasing: true), "9")
        XCTAssertNil(WorkoutWidgetControls.reps("3.5", increasing: true))
        XCTAssertNil(WorkoutWidgetControls.reps("-1", increasing: true))
    }
}
