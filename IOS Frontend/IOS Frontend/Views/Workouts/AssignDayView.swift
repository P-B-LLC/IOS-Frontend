//
//  AssignDayView.swift
//  IOS Frontend
//
//  Assign a workout (or a rest day) to a single weekday.
//

import SwiftUI

/// Pick which workout is scheduled on a given day — an existing one from the
/// library, a rest day, or a brand-new workout. Pushed from the Workouts page.
struct AssignDayView: View {
    let day: Weekday

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var creatingWorkout = false

    private var isRestDay: Bool { store.assignments[day] == nil }

    var body: some View {
        List {
            Section {
                Button {
                    store.clearAssignment(on: day)
                    dismiss()
                } label: {
                    HStack {
                        Text("Rest day (no workout)")
                            .foregroundStyle(.primary)
                        Spacer()
                        if isRestDay {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Section("Choose a workout") {
                if store.workouts.isEmpty {
                    Text("No workouts yet. Create one below.")
                        .foregroundStyle(.secondary)
                }

                ForEach(store.workouts) { workout in
                    Button {
                        store.assign(workout.id, to: day)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.name)
                                    .foregroundStyle(.primary)
                                Text("^[\(workout.exercises.count) exercise](inflect: true)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.assignments[day] == workout.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button {
                    creatingWorkout = true
                } label: {
                    Label("New Workout", systemImage: "plus")
                }
            }
        }
        .navigationTitle(day.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creatingWorkout) {
            // On save the new workout is added to the library and assigned to
            // this day; the checkmark then reflects the assignment.
            WorkoutEditorView(mode: .create) { newWorkout in
                store.assign(newWorkout.id, to: day)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AssignDayView(day: .wednesday)
    }
    .environment(WorkoutStore())
}
