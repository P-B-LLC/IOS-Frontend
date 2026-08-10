//
//  WorkoutEditorView.swift
//  IOS Frontend
//
//  Create or edit a workout: a name plus a list of exercises with set counts.
//

import SwiftUI

/// Create a new workout or edit an existing one. Presented as a sheet.
struct WorkoutEditorView: View {
    /// Whether the editor is creating a new workout or editing an existing one.
    /// `Identifiable` so it can drive a `.sheet(item:)`.
    enum Mode: Identifiable {
        case create
        case edit(Workout)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let workout): return workout.id.uuidString
            }
        }
    }

    let mode: Mode
    /// Called after a successful save (e.g. so a caller can assign the workout to a day).
    var onSaved: ((Workout) -> Void)?

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Workout

    init(mode: Mode, onSaved: ((Workout) -> Void)? = nil) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .create:
            _draft = State(initialValue: Workout(name: "", exercises: []))
        case .edit(let workout):
            _draft = State(initialValue: workout)
        }
    }

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Workout name", text: $draft.name)
                }

                Section("Exercises") {
                    if draft.exercises.isEmpty {
                        Text("No exercises yet")
                            .foregroundStyle(.secondary)
                    }

                    ForEach($draft.exercises) { $exercise in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Exercise name", text: $exercise.name)
                            Stepper(value: $exercise.sets, in: 1...20) {
                                Text("^[\(exercise.sets) set](inflect: true)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { draft.exercises.remove(atOffsets: $0) }

                    Button {
                        draft.exercises.append(Exercise(name: "", sets: 3))
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle(isCreate ? "New Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func save() {
        draft.name = trimmedName
        // Trim exercise names and drop blank ones so empty rows don't inflate
        // the workout's exercise / set counts.
        draft.exercises = draft.exercises.compactMap { exercise in
            var exercise = exercise
            exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return exercise.name.isEmpty ? nil : exercise
        }
        switch mode {
        case .create: store.addWorkout(draft)
        case .edit: store.updateWorkout(draft)
        }
        onSaved?(draft)
        dismiss()
    }
}

#Preview("Create") {
    WorkoutEditorView(mode: .create)
        .environment(WorkoutStore())
}

#Preview("Edit") {
    WorkoutEditorView(mode: .edit(WorkoutStore.sampleWorkouts[0]))
        .environment(WorkoutStore())
}
