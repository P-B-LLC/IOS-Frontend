//
//  DayWorkoutView.swift
//  IOS Frontend
//
//  A complete workout workspace for one weekday.
//

import SwiftUI

/// Creates, displays, edits, and removes the workout for a single day.
/// There is intentionally no workout-library picker until a database exists.
struct DayWorkoutView: View {
    let day: Weekday

    @Environment(WorkoutStore.self) private var store
    @State private var editor: WorkoutEditorView.Mode?
    @State private var showingRemoveConfirmation = false

    private var workout: Workout? {
        store.workout(on: day)
    }

    var body: some View {
        List {
            Section {
                overview
            }

            if let workout {
                Section("Exercises") {
                    if workout.exercises.isEmpty {
                        Label("No exercises yet", systemImage: "list.bullet.clipboard")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workout.exercises) { exercise in
                            ExerciseSummaryRow(exercise: exercise)
                        }
                    }
                }

                Section {
                    Button {
                        editor = .edit(workout)
                    } label: {
                        Label("Edit Workout", systemImage: "pencil")
                    }
                    .disabled(!store.isEditingEnabled)

                    Button(role: .destructive) {
                        showingRemoveConfirmation = true
                    } label: {
                        Label("Remove Workout", systemImage: "trash")
                    }
                    .disabled(!store.isEditingEnabled)
                }
            } else {
                Section {
                    Button {
                        editor = .create
                    } label: {
                        Label("Create Workout", systemImage: "plus.circle.fill")
                    }
                    .disabled(!store.isEditingEnabled)
                } footer: {
                    Text("Add a name, exercises, and target sets for \(day.fullName).")
                }
            }

            if let persistenceError = store.persistenceError {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Retry") {
                            store.retryPersistence()
                        }
                    }
                }
            }
        }
        .navigationTitle(day.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor) { mode in
            WorkoutEditorView(mode: mode) { savedWorkout in
                store.saveWorkout(savedWorkout, on: day)
            }
        }
        .confirmationDialog(
            "Remove \(workout?.name ?? "this workout")?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from \(day.fullName)", role: .destructive) {
                store.removeWorkout(on: day)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You can create a new workout for this day at any time.")
        }
    }

    @ViewBuilder
    private var overview: some View {
        if let workout {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Scheduled workout", systemImage: "figure.strengthtraining.traditional")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    todayBadge
                }

                Text(workout.name)
                    .font(.title2.weight(.bold))

                Text(workoutSummary(workout))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Spacer()
                    todayBadge
                }

                Text("No workout yet")
                    .font(.title3.weight(.semibold))
                Text("Build this day's workout when you're ready.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var todayBadge: some View {
        if store.today == day {
            Text("TODAY")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
    }

    private func workoutSummary(_ workout: Workout) -> String {
        let exerciseCount = workout.exercises.count
        let setCount = workout.totalSets
        let exercises = "\(exerciseCount) exercise\(exerciseCount == 1 ? "" : "s")"
        let sets = "\(setCount) set\(setCount == 1 ? "" : "s")"
        return "\(exercises) · \(sets)"
    }
}

private struct ExerciseSummaryRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(exercise.name)
            Spacer()
            Text("\(exercise.sets) set\(exercise.sets == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Empty Day") {
    NavigationStack {
        DayWorkoutView(day: .wednesday)
    }
    .environment(WorkoutStore())
}

#Preview("Scheduled Day") {
    NavigationStack {
        DayWorkoutView(day: .monday)
    }
    .environment(WorkoutStore.preview)
}
