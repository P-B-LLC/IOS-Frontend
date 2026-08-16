//
//  WorkoutPlanFields.swift
//  IOS Frontend
//
//  Reusable, customizable workout-plan controls.
//

import SwiftUI

struct WorkoutPlanFields: View {
    enum Sections {
        case all
        case identity
        case structure
    }

    @Binding var draft: Workout
    @Environment(\.workoutVisualPhase) private var phase
    /// Workouts the user already has, offered so a name is reused exactly
    /// rather than retyped slightly differently.
    var suggestions: [WorkoutSummary] = []
    var sections: Sections = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if sections != .structure {
                nameCard
                typeCard
            }

            if sections != .identity {
                if draft.type.tracksDistance {
                    distanceCard
                } else {
                    previousWorkoutSection
                    exerciseSection
                    cardioFinisherCard
                }
            }
        }
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Workout Name", systemImage: "character.cursor.ibeam")
                .font(.subheadline.weight(.semibold))
            TextField(namePlaceholder, text: $draft.name)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(phase.primaryText.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))

            nameGuidance
        }
        .workoutCard()
    }

    /// Either confirms the name will join an existing workout's history, or
    /// offers the names already in use so it can.
    @ViewBuilder
    private var nameGuidance: some View {
        if let existing = matchedWorkout {
            Label(
                "Continues your \(existing.name) history",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption2)
            .foregroundStyle(phase.accent)
        } else if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Previously used")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(phase.secondaryText)

                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(suggestions) { workout in
                            Button {
                                reuse(workout, includingIdentity: true)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: workout.type.symbolName)
                                        .font(.caption2)
                                    Text(workout.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundStyle(phase.primaryText)
                                .background(
                                    phase.primaryText.opacity(0.05),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                Text("Tap one to keep its progress together. A new name starts its own history.")
                    .font(.caption2)
                    .foregroundStyle(phase.secondaryText)
            }
        }
    }

    private var matchedWorkout: WorkoutSummary? {
        suggestions.first { WorkoutSummary.matches($0.name, draft.name) }
    }

    private var reusableLiftingWorkouts: [WorkoutSummary] {
        suggestions.filter { $0.type == .lifting && !$0.exercises.isEmpty }
    }

    @ViewBuilder
    private var previousWorkoutSection: some View {
        if !reusableLiftingWorkouts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Previously Used Workouts", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))

                Text("Reuse the exercises and target sets from an earlier lifting workout.")
                    .font(.caption)
                    .foregroundStyle(phase.secondaryText)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(reusableLiftingWorkouts) { workout in
                            Button {
                                reuse(workout, includingIdentity: false)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(workout.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text("^[\(workout.exercises.count) exercise](inflect: true)")
                                        .font(.caption2)
                                        .foregroundStyle(phase.secondaryText)
                                }
                                .frame(minWidth: 116, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .foregroundStyle(phase.primaryText)
                                .background(
                                    phase.primaryText.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Copies its exercises and target sets")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .workoutCard()
        }
    }

    private func reuse(_ workout: WorkoutSummary, includingIdentity: Bool) {
        withAnimation(.snappy) {
            if includingIdentity {
                draft.name = workout.name
                draft.type = workout.type
            }
            draft.exercises = workout.exercises.map { exercise in
                Exercise(
                    serverID: exercise.serverID,
                    serverName: exercise.serverName ?? exercise.name,
                    name: exercise.name,
                    sets: exercise.targetSets
                )
            }
        }
    }

    private var namePlaceholder: String {
        switch draft.type {
        case .lifting: return "Example: Push Day"
        case .running: return "Example: Morning Run"
        case .biking: return "Example: Long Ride"
        case .swimming: return "Example: Pool Laps"
        }
    }

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Workout Type", systemImage: "figure.mixed.cardio")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 7) {
                ForEach(WorkoutType.allCases) { type in
                    Button {
                        withAnimation(.snappy) { draft.type = type }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: type.symbolName)
                                .font(.title3)
                            Text(type.title)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(
                            draft.type == type ? phase.accent : phase.secondaryText
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    draft.type == type
                                        ? phase.accent.opacity(0.14)
                                        : phase.primaryText.opacity(0.045)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    phase.accent,
                                    lineWidth: draft.type == type ? 1.5 : 0
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(type.title)
                    .accessibilityAddTraits(
                        draft.type == type ? [.isButton, .isSelected] : .isButton
                    )
                }
            }
        }
        .workoutCard()
    }

    /// Distance workouts have nothing to plan up front and nothing to enter
    /// while training: GPS measures the distance and the session gives the time.
    private var distanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How this is logged", systemImage: "stopwatch")
                .font(.subheadline.weight(.semibold))
            Text("Start the session when you set off and end it when you finish. Repbase follows your route by GPS and works out your distance, time, and pace — there is nothing to type in.")
                .font(.caption)
                .foregroundStyle(phase.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .workoutCard()
    }

    /// Optional cardio to finish the workout on. Part of this workout, so it
    /// is planned here rather than scheduled as a second workout.
    private var cardioFinisherCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Finish With Cardio", systemImage: "figure.mixed.cardio")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if draft.cardioMachine != nil {
                    Button("Remove") {
                        withAnimation(.snappy) {
                            draft.cardioMachine = nil
                            draft.cardioTargetMinutes = nil
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            Text("Optional. Added to the end of this workout — you start it from the summary when you finish lifting.")
                .font(.caption2)
                .foregroundStyle(phase.secondaryText)

            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(CardioMachine.allCases) { machine in
                        let isSelected = draft.cardioMachine == machine
                        Button {
                            withAnimation(.snappy) {
                                draft.cardioMachine = isSelected ? nil : machine
                            }
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: machine.symbolName)
                                    .font(.title3)
                                Text(machine.title)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                            }
                            .frame(width: 78)
                            .padding(.vertical, 10)
                            .foregroundStyle(
                                isSelected
                                    ? phase.accent
                                    : phase.secondaryText
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        isSelected
                                            ? phase.accent.opacity(0.14)
                                            : phase.primaryText.opacity(0.045)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        phase.accent,
                                        lineWidth: isSelected ? 1.5 : 0
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(machine.title)
                        .accessibilityAddTraits(
                            isSelected ? [.isButton, .isSelected] : .isButton
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)

            if draft.cardioMachine != nil {
                HStack {
                    Text("Target")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Button {
                        draft.cardioTargetMinutes = max(
                            5,
                            (draft.cardioTargetMinutes ?? 15) - 5
                        )
                    } label: {
                        Image(systemName: "minus").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)

                    Text("\(draft.cardioTargetMinutes ?? 15) min")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 62)

                    Button {
                        draft.cardioTargetMinutes = min(
                            120,
                            (draft.cardioTargetMinutes ?? 15) + 5
                        )
                    } label: {
                        Image(systemName: "plus").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .workoutCard()
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exercises")
                        .font(.headline)
                    Text("Add as many as you need and set a target for each.")
                        .font(.caption)
                        .foregroundStyle(phase.secondaryText)
                }
                Spacer()
                Text("\(draft.exercises.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(phase.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(phase.accent.opacity(0.12), in: Capsule())
            }

            if draft.exercises.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.title2)
                        .foregroundStyle(phase.accent)
                    Text("Start with your first exercise")
                        .font(.subheadline.weight(.semibold))
                    Text("You can always reorder, edit, or add more later.")
                        .font(.caption)
                        .foregroundStyle(phase.secondaryText)
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
    @Environment(\.workoutVisualPhase) private var phase

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
                    .foregroundStyle(phase.accent)
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
                        .foregroundStyle(phase.secondaryText)
                }
                .accessibilityLabel("Exercise options")
            }

            TextField("Exercise name", text: $exercise.name)
                .textInputAutocapitalization(.words)
                .font(.body.weight(.medium))
                .padding(12)
                .background(phase.primaryText.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Sets")
                        .font(.subheadline.weight(.semibold))
                    Text("Weight and reps are entered during the session.")
                        .font(.caption2)
                        .foregroundStyle(phase.secondaryText)
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
