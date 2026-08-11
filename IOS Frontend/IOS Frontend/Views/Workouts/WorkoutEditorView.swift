//
//  WorkoutEditorView.swift
//  IOS Frontend
//
//  Create or edit a workout: a name plus a list of exercises with set counts.
//

import SwiftUI

/// Create a new workout or edit an existing one. Presented by a day screen.
/// The editor returns a finished value; the day owns where that workout lives.
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
    /// Called after a successful save so the owning day can persist the workout.
    var onSaved: ((Workout) -> Void)?

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
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Exercise name", text: $exercise.name)
                                Stepper(value: $exercise.sets, in: 1...20) {
                                    Text("^[\(exercise.sets) set](inflect: true)")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button(role: .destructive) {
                                removeExercise(id: exercise.id)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove exercise")
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
        onSaved?(draft)
        dismiss()
    }

    private func removeExercise(id: Exercise.ID) {
        draft.exercises.removeAll { $0.id == id }
    }
}

#Preview("Create") {
    WorkoutEditorView(mode: .create)
}

#Preview("Edit") {
    WorkoutEditorView(mode: .edit(WorkoutStore.previewWorkouts[0]))
}
