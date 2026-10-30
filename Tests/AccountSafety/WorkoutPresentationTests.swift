import Foundation
import XCTest

/// Wiring guards supplement the transport/state tests. Visual and interaction
/// QA still runs in the simulator; these do not claim to render SwiftUI.
final class WorkoutPresentationTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        let url = URL(fileURLWithPath: root).appendingPathComponent("IOS Frontend/IOS Frontend/\(path)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testDayShowsNamedCardsWithoutNoOpViewOrHiddenWorkoutPager() throws {
        let day = try source("Views/Workouts/DayWorkoutView.swift")
        XCTAssertFalse(day.contains("headerActionLabel(\"View\")"))
        XCTAssertFalse(day.contains("private var workoutPager"))
        XCTAssertTrue(day.contains("ForEach(plannedWorkouts) { planned in"))
        XCTAssertTrue(day.contains("workoutCardHeader(workout, completed: false)"))
        XCTAssertTrue(day.contains("Text(workout.name)"))
        XCTAssertTrue(day.contains("DayWorkoutCardSurface(highlighted:"))
        XCTAssertTrue(day.contains("store.startSession(on: day, workoutID: workout.id)"))
    }

    func testSaveConfirmationUsesConfirmedReadBackIdentity() throws {
        let day = try source("Views/Workouts/DayWorkoutView.swift")
        XCTAssertTrue(day.contains("let problem = await store.saveWorkoutReportingFailure(savedWorkout, on: day)"))
        XCTAssertTrue(day.contains("if problem == nil {"))
        XCTAssertTrue(day.contains("highlightedWorkoutID = store.lastSavedWorkoutID"))
        XCTAssertTrue(day.contains("reader.scrollTo(highlightedWorkoutID"))
    }

    func testSelectionsAreVisibleBeforeTheExerciseCatalog() throws {
        let builder = try source("Views/Workouts/GuidedWorkoutBuilder.swift")
        let picker = try XCTUnwrap(builder.range(of: "private var exercisePicker:"))
        let selected = try XCTUnwrap(builder.range(of: "selectedExercises", range: picker.upperBound..<builder.endIndex))
        // The catalogue is the shared picker the session's add sheet uses too.
        let catalog = try XCTUnwrap(builder.range(of: "ExerciseCatalogPicker(", range: picker.upperBound..<builder.endIndex))
        XCTAssertLessThan(selected.lowerBound, catalog.lowerBound)
        XCTAssertTrue(builder.contains("workout-builder-selected-exercises"))
        XCTAssertTrue(builder.contains("Not saved yet"))
        XCTAssertTrue(builder.contains("hasDuplicateSavedName"))
    }

    func testWorkoutDraftRestorationRequiresAnExplicitChoice() throws {
        let editor = try source("Views/Workouts/WorkoutEditorView.swift")
        let recovery = try source("Views/Shared/RecoverableDraft.swift")
        XCTAssertTrue(editor.contains("confirmRestoration: true"))
        XCTAssertTrue(editor.contains("Workout(name: \"\", exercises: [])"))
        XCTAssertTrue(recovery.contains("if confirmRestoration, restored != value"))
        XCTAssertTrue(recovery.contains("Button(\"Continue draft\")"))
        XCTAssertTrue(recovery.contains("Button(\"Discard draft\", role: .destructive)"))
        XCTAssertTrue(recovery.contains("scope == EditorDraftRecovery.shared.scope"))
    }

    func testCompletionBadgesAndUndoUseTheSavedWorkoutIdentity() throws {
        let day = try source("Views/Workouts/DayWorkoutView.swift")
        XCTAssertTrue(day.contains("store.isCompleted(workout: planned, on: dayDate)"))
        XCTAssertTrue(day.contains("store.finishedSessions(workout: workout, on: dayDate)"))
        XCTAssertFalse(day.contains("workoutName: workout.name"))
        XCTAssertTrue(try source("Views/Home/GuidedHomeView.swift").contains("isCompleted(workout: workout, on: selectedDate)"))
        XCTAssertTrue(try source("Views/Workouts/TrainingDashboardContent.swift").contains("isCompleted(workout: $0, on:"))
        XCTAssertTrue(try source("Views/Planner/PlannerWorkoutCompletion.swift").contains("isCompleted(workoutServerID: workoutID, on: date)"))
    }
}
