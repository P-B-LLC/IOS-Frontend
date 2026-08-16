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
        case build(Workout)
        case edit(Workout)

        var id: String {
            switch self {
            case .create: return "create"
            case .build(let workout): return "build-\(workout.id.uuidString)"
            case .edit(let workout): return workout.id.uuidString
            }
        }
    }

    let mode: Mode
    /// Existing workout names, passed in rather than read from the
    /// environment so previews stand alone.
    var suggestions: [WorkoutSummary] = []
    var onSaved: ((Workout) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Workout

    init(
        mode: Mode,
        suggestions: [WorkoutSummary] = [],
        onSaved: ((Workout) -> Void)? = nil
    ) {
        self.mode = mode
        self.suggestions = suggestions
        self.onSaved = onSaved
        switch mode {
        case .create:
            _draft = State(initialValue: Workout(name: "", exercises: []))
        case .build(let workout):
            _draft = State(initialValue: workout)
        case .edit(let workout):
            _draft = State(initialValue: workout)
        }
    }

    private var isCreate: Bool {
        switch mode {
        case .create, .build: return true
        case .edit: return false
        }
    }

    private var sections: WorkoutPlanFields.Sections {
        if case .build = mode { return .structure }
        return .all
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "New Workout"
        case .build: return "Build Workout"
        case .edit: return "Edit Workout"
        }
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            editorScreen(timeOfDay: HomeTimeOfDay(date: context.date))
        }
    }

    private func editorScreen(timeOfDay: HomeTimeOfDay) -> some View {
        let visualPhase: WorkoutVisualPhase = timeOfDay.usesDarkAppearance ? .focus : .prepare

        return NavigationStack {
            VStack(spacing: 0) {
                workoutHeader(timeOfDay: timeOfDay)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(draft.type == .lifting ? "LIFTING · \(draft.name.isEmpty ? "NEW WORKOUT" : draft.name.uppercased())" : draft.type.title.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(timeOfDay.accent)
                            .lineLimit(1)
                        Text(isCreate ? "Build your workout" : "Customize your plan")
                            .font(.title2.weight(.bold))
                        Text("Set the structure now. Log weight and reps when you train.")
                            .font(.subheadline)
                            .foregroundStyle(timeOfDay.secondaryText)
                    }

                    WorkoutPlanFields(
                        draft: $draft,
                        suggestions: suggestions,
                        sections: sections
                    )

                    Button {
                        save()
                    } label: {
                        Label(isCreate ? "Create Workout" : "Save Changes", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WorkoutPrimaryButtonStyle(phase: visualPhase))
                    .disabled(!canSave)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
        }
    }

    private func workoutHeader(timeOfDay: HomeTimeOfDay) -> some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(timeOfDay.secondaryText)
                .buttonStyle(.plain)

            Spacer()

            Button {
                save()
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .buttonStyle(RepbaseAccentCapsuleButtonStyle(timeOfDay: timeOfDay))
            .disabled(!canSave)
        }
        .overlay {
            Text(navigationTitle)
                .font(.headline)
                .foregroundStyle(timeOfDay.canvasPrimaryText)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
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
