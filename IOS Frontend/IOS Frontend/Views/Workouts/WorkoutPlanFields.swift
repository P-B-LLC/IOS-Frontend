//
//  WorkoutPlanFields.swift
//  IOS Frontend
//
//  Reusable, customizable workout-plan controls.
//

import SwiftUI

struct WorkoutPlanFields: View {
    @Binding var draft: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Workout Name", systemImage: "character.cursor.ibeam")
                    .font(.subheadline.weight(.semibold))
                TextField("Example: Push Day", text: $draft.name)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            }
            .workoutCard()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exercises")
                        .font(.headline)
                    Text("Add as many as you need and set a target for each.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(draft.exercises.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            if draft.exercises.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text("Start with your first exercise")
                        .font(.subheadline.weight(.semibold))
                    Text("You can always reorder, edit, or add more later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .workoutCard()
            }

            ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { index, exercise in
                ExercisePlanEditorCard(
                    position: index + 1,
                    exercise: binding(for: exercise.id),
                    canMoveUp: index > 0,
                    canMoveDown: index < draft.exercises.count - 1,
                    onMoveUp: { moveExercise(id: exercise.id, offset: -1) },
                    onMoveDown: { moveExercise(id: exercise.id, offset: 1) },
                    onRemove: { removeExercise(id: exercise.id) }
                )
            }

            Button {
                withAnimation(.snappy) {
                    draft.exercises.append(Exercise(name: "", sets: 3))
                }
            } label: {
                Label("Add Exercise", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func binding(for id: Exercise.ID) -> Binding<Exercise> {
        Binding(
            get: {
                draft.exercises.first(where: { $0.id == id }) ?? Exercise(id: id, name: "")
            },
            set: { updated in
                guard let index = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
                draft.exercises[index] = updated
            }
        )
    }

    private func removeExercise(id: Exercise.ID) {
        withAnimation(.snappy) {
            draft.exercises.removeAll { $0.id == id }
        }
    }

    private func moveExercise(id: Exercise.ID, offset: Int) {
        guard let current = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        let destination = current + offset
        guard draft.exercises.indices.contains(destination) else { return }
        withAnimation(.snappy) {
            draft.exercises.swapAt(current, destination)
        }
    }
}

private struct ExercisePlanEditorCard: View {
    let position: Int
    @Binding var exercise: Exercise
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Exercise \(position)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Menu {
                    Button("Move Up", systemImage: "arrow.up", action: onMoveUp)
                        .disabled(!canMoveUp)
                    Button("Move Down", systemImage: "arrow.down", action: onMoveDown)
                        .disabled(!canMoveDown)
                    Divider()
                    Button("Remove Exercise", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Exercise options")
            }

            TextField("Exercise name", text: $exercise.name)
                .textInputAutocapitalization(.words)
                .font(.body.weight(.medium))
                .padding(12)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Sets")
                        .font(.subheadline.weight(.semibold))
                    Text("Weight and reps are entered during the session.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 12) {
                    Button {
                        exercise.sets = max(1, exercise.sets - 1)
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .disabled(exercise.sets <= 1)
                    .accessibilityLabel("Decrease target sets")

                    Text("\(exercise.sets)")
                        .font(.headline.monospacedDigit())
                        .frame(minWidth: 22)

                    Button {
                        exercise.sets += 1
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Increase target sets")
                }
            }
        }
        .workoutCard()
    }
}
