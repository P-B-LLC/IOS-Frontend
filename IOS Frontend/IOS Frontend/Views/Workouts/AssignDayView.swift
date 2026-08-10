//
//  AssignDayView.swift
//  IOS Frontend
//
//  Assign a workout (or a rest day) to a single weekday.
//

import SwiftUI

/// Pick what's scheduled on a given day: type a custom workout name, choose an
/// existing workout from the library, build a new one with exercises, or make
/// it a rest day. Pushed from the Workouts page.
struct AssignDayView: View {
    let day: Weekday

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var customName = ""
    @State private var creatingWorkout = false

    private var isRestDay: Bool { store.assignments[day] == nil }

    private var trimmedCustomName: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            // Primary path: let the user type any workout name for this day.
            Section {
                HStack {
                    TextField("e.g. Leg Day", text: $customName)
                        .submitLabel(.done)
                        .onSubmit(assignCustomWorkout)
                    Button("Assign", action: assignCustomWorkout)
                        .buttonStyle(.borderless)
                        .disabled(trimmedCustomName.isEmpty)
                }
            } header: {
                Text("Name this day's workout")
            } footer: {
                Text("Type any name to schedule it on \(day.fullName). You can add exercises to it later.")
            }

            Section("Or choose an existing workout") {
                if store.workouts.isEmpty {
                    Text("No workouts yet.")
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
                    Label("Build a new workout…", systemImage: "plus")
                }

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

    /// Create a workout from the typed name, add it to the library, and schedule
    /// it on this day. Exercises can be added later by editing it.
    private func assignCustomWorkout() {
        let name = trimmedCustomName
        guard !name.isEmpty else { return }
        let workout = Workout(name: name)
        store.addWorkout(workout)
        store.assign(workout.id, to: day)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        AssignDayView(day: .wednesday)
    }
    .environment(WorkoutStore())
}
