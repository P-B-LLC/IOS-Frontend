import Foundation
import XCTest
@testable import AccountSafety

final class WorkoutFlowTests: XCTestCase {
    func testDayTurnsCompleteOnlyAfterEveryScheduledWorkoutAndNoActiveSession() {
        XCTAssertFalse(WorkoutFocusPolicy.dayIsComplete(scheduledCompletions: [], hasActiveSession: false))
        XCTAssertFalse(WorkoutFocusPolicy.dayIsComplete(scheduledCompletions: [true, false], hasActiveSession: false))
        XCTAssertFalse(WorkoutFocusPolicy.dayIsComplete(scheduledCompletions: [true], hasActiveSession: true))
        XCTAssertTrue(WorkoutFocusPolicy.dayIsComplete(scheduledCompletions: [true], hasActiveSession: false))
        XCTAssertTrue(WorkoutFocusPolicy.dayIsComplete(scheduledCompletions: [true, true], hasActiveSession: false))
    }

    func testWeightConversionPreservesKilogramWireValuesAndInvalidInput() {
        XCTAssertEqual(WorkoutWeightUnit.imperial.kilograms(display: "135"), "61.23")
        // Pounds are shown to a tenth from two-decimal kilograms, so 135 lb
        // typed in comes back as 135 rather than 134.99.
        XCTAssertEqual(WorkoutWeightUnit.imperial.display(kilograms: "61.23"), "135")
        XCTAssertEqual(WorkoutWeightUnit.metric.kilograms(display: "12,5"), "12.5")
        XCTAssertEqual(WorkoutWeightUnit.metric.kilograms(display: ""), "")
        XCTAssertEqual(WorkoutWeightUnit.imperial.kilograms(display: "0"), "0")
        XCTAssertEqual(WorkoutWeightUnit.imperial.kilograms(display: ".5"), "0.23")
        XCTAssertEqual(WorkoutWeightUnit.imperial.kilograms(display: "12junk"), "12junk")
    }

    /// Arabic and Devanagari keyboards type their own digits; the set has to
    /// log all the same.
    func testNativeKeyboardDigitsAreReadAsNumbers() {
        XCTAssertEqual(NumberInput.latinDigits("٦٠٫٥"), "60.5")
        XCTAssertEqual(NumberInput.latinDigits("६०"), "60")
        XCTAssertEqual(NumberInput.latinDigits("12junk"), "12junk")
        XCTAssertEqual(WorkoutWeightUnit.metric.kilograms(display: "٦٠"), "60")
        XCTAssertEqual(WorkoutWeightUnit.imperial.kilograms(display: "١٣٥"), "61.23")
        var draft = ActivityLogDraft(activity: .running)
        draft.minutes = "٤٥"
        XCTAssertEqual(draft.durationSeconds, 2700)
    }
    func testSwitchingPreservesRequestedExerciseEvenWhenItIsComplete() {
        let a = UUID(), b = UUID()
        let progress = [WorkoutFocusPolicy.Progress(id: a, pendingSets: 0), .init(id: b, pendingSets: 4)]
        XCTAssertEqual(WorkoutFocusPolicy.resolve(selected: a, exercises: progress), a)
        XCTAssertEqual(WorkoutFocusPolicy.resolve(selected: b, exercises: progress), b)
        XCTAssertEqual(progress.map(\.pendingSets), [0, 4])
    }

    func testOnlyConfirmedCompletionShouldAdvanceToNextUnfinishedExercise() {
        let a = UUID(), b = UUID(), c = UUID()
        let progress = [WorkoutFocusPolicy.Progress(id: a, pendingSets: 1), .init(id: b, pendingSets: 0), .init(id: c, pendingSets: 2)]
        XCTAssertEqual(WorkoutFocusPolicy.resolve(selected: a, exercises: progress), a)
        XCTAssertEqual(WorkoutFocusPolicy.next(after: a, exercises: progress), c)
        XCTAssertEqual(WorkoutFocusPolicy.next(after: c, exercises: progress), a)
    }

    func testRestoredOrStaleSelectionChoosesFirstUnfinishedAndEmptySessionIsSafe() {
        let a = UUID(), b = UUID()
        let progress = [WorkoutFocusPolicy.Progress(id: a, pendingSets: 0), .init(id: b, pendingSets: 2)]
        XCTAssertEqual(WorkoutFocusPolicy.resolve(selected: UUID(), exercises: progress), b)
        XCTAssertNil(WorkoutFocusPolicy.resolve(selected: nil, exercises: []))
        XCTAssertNil(WorkoutFocusPolicy.next(after: a, exercises: [.init(id: a, pendingSets: 0)]))
    }

    func testStepGoalDoesNotCelebrateOpeningAnAlreadyCompleteDay() {
        var gate = StepGoalCelebrationGate()
        let day = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(gate.observe(day: day, steps: 9_000, goal: 8_000))
        XCTAssertFalse(gate.observe(day: day, steps: 10_000, goal: 8_000))
    }

    func testActualCrossingCelebratesOnceEvenAfterHealthCorrection() {
        var gate = StepGoalCelebrationGate()
        let day = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(gate.observe(day: day, steps: 7_999, goal: 8_000))
        XCTAssertTrue(gate.observe(day: day, steps: 8_000, goal: 8_000))
        XCTAssertFalse(gate.observe(day: day, steps: 7_990, goal: 8_000))
        XCTAssertFalse(gate.observe(day: day, steps: 8_005, goal: 8_000))
    }

    func testGoalEditsMissingDataAndNewDayDoNotInventCrossings() {
        var gate = StepGoalCelebrationGate()
        let day = Date(timeIntervalSince1970: 0), tomorrow = Date(timeIntervalSince1970: 86_400)
        XCTAssertFalse(gate.observe(day: day, steps: 6_000, goal: 8_000))
        gate.rebase(day: day, steps: 6_000, goal: 5_000)
        XCTAssertFalse(gate.observe(day: day, steps: 6_001, goal: 5_000))
        XCTAssertFalse(gate.observe(day: tomorrow, steps: 8_100, goal: 8_000))
        XCTAssertFalse(gate.observe(day: tomorrow, steps: nil, goal: 8_000))
        XCTAssertFalse(gate.observe(day: tomorrow, steps: 8_200, goal: 8_000))
        XCTAssertFalse(gate.observe(day: tomorrow, steps: 9_000, goal: 0))
    }
}
