//
//  WorkoutsView.swift
//  IOS Frontend
//
//  The Workouts page: this week's schedule + the user's workout library.
//

import SwiftUI

/// The Workouts page. "This Week" lets the user tap a day to assign a workout;
/// "My Workouts" is the library, where workouts are created and edited. Reads
/// and writes the shared `WorkoutStore` single source of truth.
struct WorkoutsView: View {
    @Environment(WorkoutStore.self) private var store
    @State private var editor: WorkoutEditorView.Mode?

    var body: some View {
        List {
            Section("This Week") {
                ForEach(Weekday.allCases) { day in
                    NavigationLink {
                        AssignDayView(day: day)
                    } label: {
                        DayAssignmentRow(day: day, workout: store.workout(on: day))
                    }
                }
            }

            Section("My Workouts") {
                if store.workouts.isEmpty {
                    Text("No workouts yet. Tap + to create one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.workouts) { workout in
                        Button {
                            editor = .edit(workout)
                        } label: {
                            WorkoutSummaryRow(workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        offsets.map { store.workouts[$0] }.forEach(store.deleteWorkout)
                    }
                }
            }
        }
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editor = .create
                } label: {
                    Label("New Workout", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { mode in
            WorkoutEditorView(mode: mode)
        }
    }
}

/// A "This Week" row: the weekday and its assigned workout (or an Assign prompt).
private struct DayAssignmentRow: View {
    let day: Weekday
    let workout: Workout?

    var body: some View {
        HStack {
            Text(day.fullName)
            Spacer()
            if let workout {
                Text(workout.name)
                    .foregroundStyle(.secondary)
            } else {
                Text("Assign")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// A "My Workouts" row: the workout name and a summary of its contents.
private struct WorkoutSummaryRow: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workout.name)
                .foregroundStyle(.primary)
            Text("^[\(workout.exercises.count) exercise](inflect: true) · ^[\(workout.totalSets) set](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutsView()
    }
    .environment(WorkoutStore())
}
