//
//  ActiveLiftingSessionView.swift
//  IOS Frontend
//
//  The lifting session in progress: every exercise and set on one page.
//

import SwiftUI

/// The live workout.
///
/// Replaces a screen that showed one set at a time and hid the rest of the
/// workout behind a "switch exercise" sheet. Everything is on one page now:
/// each exercise is a card with its sets as a table, the current set is
/// marked, last time's numbers sit beside today's, and logging is one tap on
/// the row's check. Editing happens where the thing being edited is -- a set's
/// kind from its number, an exercise's rest from its card -- so nothing during
/// a workout needs a trip to another screen.
///
/// Focus, inputs and the rest all live in the store's session, which is
/// checkpointed, so leaving this screen or the app changes nothing.
struct ActiveLiftingSessionView: View {
    let day: Weekday
    let onFinish: () -> Void
    /// Asks to delete the whole session. The caller confirms first.
    let onDiscard: () -> Void
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: SessionField?
    @State private var weightInputs: [UUID: String] = [:]
    @State private var reordering = false
    @State private var adding = false
    private let phase = WorkoutVisualPhase.focus

    var body: some View {
        if let session = store.activeSession(on: day) {
            let focused = store.focusedExercise(in: session)
            VStack(alignment: .leading, spacing: 14) {
                header(session)
                if !session.structureChanges.isEmpty { changedNotice }
                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                    SessionExerciseCard(
                        day: day,
                        exercise: exercise,
                        position: index + 1,
                        count: session.exercises.count,
                        isFocused: exercise.id == focused?.id,
                        others: session.exercises.filter { $0.id != exercise.id && ($0.supersetGroup == nil || $0.supersetGroup != exercise.supersetGroup) },
                        focusedField: $focusedField,
                        weightInputs: $weightInputs,
                        onReorder: { reordering = true },
                        onRemove: { Task { await store.removeSessionExercise(on: day, exerciseID: exercise.id) } }
                    )
                    .id(exercise.id)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                }
                editActions(session)
                if session.totalSetCount > 0, session.loggedSetCount == session.totalSetCount {
                    Button(action: onFinish) {
                        HStack { Text("Finish workout"); Spacer(); Image(systemName: "checkmark") }
                    }
                    .buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
                    .disabled(store.isSaving || store.hasPendingSetChanges || store.isRecoveringWorkouts)
                }
                discardButton
            }
            .animation(.snappy(duration: 0.25), value: session.exercises.map(\.id))
            .onChange(of: store.preferences.weightUnit) {
                // Typed text belongs to the unit it was typed in. What is
                // shown is worked out again from the stored kilograms.
                weightInputs = [:]
            }
            .onChange(of: session.loggedSetCount) {
                for set in session.exercises.flatMap(\.sets) where set.isLogged {
                    weightInputs.removeValue(forKey: set.id)
                }
            }
            .sheet(isPresented: $reordering) { SessionReorderSheet(day: day) }
            .sheet(isPresented: $adding) { AddSessionExerciseSheet(day: day) }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button { move(by: -1, in: session) } label: { Image(systemName: "chevron.up") }
                        .accessibilityLabel("Previous field")
                    Button { move(by: 1, in: session) } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Next field")
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    // MARK: - Header

    private func header(_ session: ActiveWorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { focusedField = nil; dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.community(.subheadline, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse workout, keep session running")
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.workoutName)
                        .font(.community(.headline))
                        .lineLimit(1)
                    Text(session.startedAt, style: .timer)
                        .font(.community(.caption, weight: .semibold).monospacedDigit())
                        .foregroundStyle(phase.secondaryText)
                        .accessibilityLabel("Workout time")
                }
                Spacer(minLength: 8)
                Button("Finish", action: onFinish)
                    .font(.community(.subheadline, weight: .bold))
                    .foregroundStyle(phase.onPrimaryAction)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(phase.primaryActionSurface, in: Capsule())
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                    .disabled(store.isSaving || store.hasPendingSetChanges || store.isRecoveringWorkouts)
            }

            HStack(spacing: 14) {
                stat(value: "\(session.loggedSetCount)/\(session.totalSetCount)", label: "Sets")
                stat(value: "\(session.completedExerciseCount)/\(session.exercises.count)", label: "Exercises")
                if session.loggedVolumeKilograms > 0 {
                    stat(value: store.preferences.weightUnit.formatted(kilograms: session.loggedVolumeKilograms), label: "Volume")
                }
                Spacer(minLength: 0)
                WeightUnitToggle(compact: true)
            }

            ProgressView(value: Double(session.loggedSetCount), total: Double(max(session.totalSetCount, 1)))
                .tint(phase.accent)
                .accessibilityLabel("Workout progress")
                .accessibilityValue("\(session.loggedSetCount) of \(session.totalSetCount) sets logged")
        }
    }

    private func stat(value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.community(.subheadline, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.community(size: 10, weight: .semibold))
                .foregroundStyle(phase.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var changedNotice: some View {
        Label {
            Text("Changed from your plan. You’ll choose at Finish whether to keep it for next time.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "pencil.and.list.clipboard")
        }
        .font(.community(.caption))
        .foregroundStyle(phase.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(phase.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func editActions(_ session: ActiveWorkoutSession) -> some View {
        HStack(spacing: 10) {
            Button { adding = true } label: {
                Label("Add exercise", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.plain)
            .foregroundStyle(phase.accent)
            .background(phase.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button { reordering = true } label: {
                Label("Reorder", systemImage: "arrow.up.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.plain)
            .foregroundStyle(phase.primaryText)
            .background(phase.cardBorder.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(session.exercises.count < 2)
        }
        .font(.community(.subheadline, weight: .semibold))
    }

    /// At the end of the workout, where somebody who started the wrong one,
    /// or started by accident, looks for a way out. It only asks; deleting
    /// happens after the confirmation the caller shows.
    private var discardButton: some View {
        Button(role: .destructive, action: { focusedField = nil; onDiscard() }) {
            Label("Discard workout", systemImage: "trash")
                .font(.community(.subheadline, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(RepbaseDesign.danger)
        .background(RepbaseDesign.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 6)
        .disabled(store.isSaving || store.hasPendingSetChanges)
        .accessibilityHint("Deletes this session and every set logged in it. Asks first.")
        .accessibilityIdentifier("session-discard")
    }

    /// Moves the keyboard along the unlogged sets: weight, then reps, then the
    /// next set's weight, across exercises in order.
    private func move(by offset: Int, in session: ActiveWorkoutSession) {
        let fields = session.exercises.flatMap { exercise in
            exercise.sets.filter { !$0.isLogged }.flatMap { [SessionField.weight($0.id), .reps($0.id)] }
        }
        guard let current = focusedField, let index = fields.firstIndex(of: current) else {
            focusedField = fields.first
            return
        }
        let next = index + offset
        focusedField = fields.indices.contains(next) ? fields[next] : nil
    }
}
