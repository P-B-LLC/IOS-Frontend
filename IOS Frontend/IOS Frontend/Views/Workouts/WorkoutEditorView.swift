//
//  WorkoutEditorView.swift
//  IOS Frontend
//
//  Create or edit a workout plan.
//

import SwiftUI

struct WorkoutEditorView: View {
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

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isCreate ? "Build your workout" : "Customize your plan")
                            .font(.title2.weight(.bold))
                        Text("Set the structure now. Log weight and reps when you train.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    WorkoutPlanFields(draft: $draft)

                    Button {
                        save()
                    } label: {
                        Label(isCreate ? "Create Workout" : "Save Changes", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WorkoutPrimaryButtonStyle(phase: .prepare))
                    .disabled(!canSave)
                }
                .padding()
            }
            .background { WorkoutPhaseBackground(phase: .prepare) }
            .workoutVisualPhase(.prepare)
            .tint(WorkoutVisualPhase.prepare.accent)
            .navigationTitle(isCreate ? "New Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.exercises = draft.exercises.compactMap { exercise in
            var exercise = exercise
            exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return exercise.name.isEmpty ? nil : exercise
        }
        onSaved?(draft)
        dismiss()
    }
}

#Preview("Create") {
    WorkoutEditorView(mode: .create)
}

#Preview("Edit") {
    WorkoutEditorView(mode: .edit(WorkoutStore.previewWorkouts[0]))
}
