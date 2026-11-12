#if DEBUG
import SwiftUI

/// Isolated native visual/gesture validation, not a signed-in or saved workout.
/// This wrapper deliberately bypasses WorkoutEditorView's draft recovery. The
/// store has no account/repository and Save has no network callback. Normal
/// builds never select this root without the explicit DEBUG preview flag.
struct WorkoutFlowPreviewScreen: View {
    let scenario: String
    @State private var draft: Workout
    @State private var store: WorkoutStore

    init(scenario: String) {
        self.scenario = scenario
        var workout = Self.workout()
        if scenario == "builder-reordered" {
            // Exercise the same value-preserving operation as the real list.
            // This is a state illustration, not evidence of a touch gesture.
            workout.exercises = WorkoutExerciseOrder.moving(
                workout.exercises, fromOffsets: IndexSet(integer: 11), toOffset: 0
            )
        }
        let previewStore = scenario == "session-units"
            ? WorkoutStore.previewActiveSession : WorkoutStore.previewWithLibrary
        previewStore.preferences.adoptAccountUnit(.metric)
        _draft = State(initialValue: workout)
        _store = State(initialValue: previewStore)
    }

    var body: some View {
        NavigationStack {
            if scenario == "session-units" {
                DayWorkoutView(day: store.activeSession?.day ?? .monday)
            } else {
                GuidedWorkoutBuilder(
                    draft: $draft,
                    suggestions: [],
                    startsAtReview: scenario == "builder-units",
                    isSaving: false,
                    onSave: { /* Visual fixture: never save a user workout. */ },
                    startsAtExercises: scenario != "builder-units"
                )
            }
        }
        .environment(store)
    }

    /// Fixed local row IDs let native tests follow a moved card across index
    /// changes. No ID here is used as a server resource or account identifier.
    private static func workout() -> Workout {
        let names = [
            "Bench Press", "Incline Dumbbell Press", "Cable Fly", "Dips",
            "Lateral Raise (Dumbbell)", "Straight Arm Pullover (Dumbbell)",
            "Face Pull (Cable)", "Upright Row (Barbell)", "Bicep Curl (Dumbbell)",
            "Overhead Triceps Extension (Dumbbell)", "Hanging Crunch", "Reverse Fly (Dumbbell)"
        ]
        let exercises = names.enumerated().map { index, name in
            Exercise(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                name: name, sets: 3, restSeconds: 60,
                supersetGroup: index == 7 || index == 8 ? 1 : nil,
                targetReps: 12, targetWeightKilograms: index == 0 ? "60" : "10"
            )
        }
        return Workout(name: "Chest & Arms", exercises: exercises)
    }
}
#endif
