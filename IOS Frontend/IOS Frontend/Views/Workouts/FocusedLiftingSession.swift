import SwiftUI
import UIKit

/// Focus is UI state only. All set input stays in the recoverable store.
struct FocusedLiftingSession: View {
    let day: Weekday
    let onFinish: () -> Void
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedExerciseID: UUID?
    @State private var switching = false
    @State private var editTarget: SetEditTarget?
    @State private var editingSetID: UUID?
    @State private var weightUnit: WorkoutWeightUnit = .metric
    @State private var unitLoaded = false
    @State private var weightInputs: [UUID: String] = [:]
    @FocusState private var inputFocused: Bool
    private let phase = WorkoutVisualPhase.focus

    private struct SetEditTarget: Identifiable {
        let exerciseID: UUID
        let setID: UUID
        var id: UUID { setID }
    }

    private var session: ActiveWorkoutSession? { store.activeSession(on: day) }
    private var exercise: SessionExerciseDraft? {
        guard let session else { return nil }
        let id = WorkoutFocusPolicy.resolve(selected: selectedExerciseID, exercises: progress(session))
        return session.exercises.first { $0.id == id }
    }

    private func progress(_ session: ActiveWorkoutSession) -> [WorkoutFocusPolicy.Progress] {
        session.exercises.map { .init(id: $0.id, pendingSets: $0.sets.filter { !$0.isLogged }.count) }
    }

    var body: some View {
        if let session, let exercise {
            VStack(alignment: .leading, spacing: 24) {
                sessionHeader(session)
                VStack(alignment: .leading, spacing: 8) {
                    Text("EXERCISE \((session.exercises.firstIndex { $0.id == exercise.id } ?? 0) + 1) OF \(session.exercises.count)")
                        .font(.community(.caption2, weight: .bold)).foregroundStyle(phase.accent)
                    Text(exercise.name).font(.community(.largeTitle, weight: .bold))
                    Text("One set at a time. You’re making progress.")
                        .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
                }
                if let set = exercise.sets.first(where: { $0.id == editingSetID && !$0.isLogged })
                    ?? exercise.sets.first(where: { !$0.isLogged }) {
                    setEditor(set, exercise: exercise)
                } else {
                    Label("All sets logged for this exercise", systemImage: "checkmark.circle.fill")
                        .font(.community(.headline)).foregroundStyle(RepbaseDesign.success)
                }
                history(exercise)
                if let next = session.exercises.first(where: { $0.id != exercise.id && $0.sets.contains { !$0.isLogged } }) {
                    Button { switchTo(next.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("SWITCH TO THIS · \(next.sets.count) SETS").font(.community(.caption2, weight: .bold)).foregroundStyle(phase.secondaryText)
                                Text(next.name).font(.community(.headline))
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(16).workoutOutline(radius: 16)
                    }.buttonStyle(.plain).disabled(store.hasPendingSetChanges)
                }
                Button { switching = true } label: { Text("Switch exercise · View all").frame(minHeight: 44) }
                    .font(.community(.subheadline, weight: .bold)).foregroundStyle(phase.accent)
                    .disabled(store.hasPendingSetChanges)
                if session.loggedSetCount == session.totalSetCount {
                    Button("Finish workout", action: onFinish)
                        .buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
                        .disabled(store.isSaving || store.hasPendingSetChanges)
                }
            }
            .onAppear { if selectedExerciseID == nil { selectedExerciseID = exercise.id } }
            .task(id: session.id) {
                weightUnit = (try? await store.preferredWeightUnit()) ?? .metric
                unitLoaded = true
            }
            .onChange(of: session.loggedSetCount) { old, new in
                for set in session.exercises.flatMap(\.sets) where set.isLogged { weightInputs.removeValue(forKey: set.id) }
                if new > old { editingSetID = nil }
                guard new > old,
                      let current = session.exercises.first(where: { $0.id == selectedExerciseID }),
                      current.sets.allSatisfy(\.isLogged) else { return }
                if let next = WorkoutFocusPolicy.next(after: current.id, exercises: progress(session)) {
                    selectedExerciseID = next
                }
            }
            .sheet(isPresented: $switching) { switcher(session) }
            .confirmationDialog("Edit this logged set?", isPresented: Binding(
                get: { editTarget != nil }, set: { if !$0 { editTarget = nil } }), titleVisibility: .visible) {
                Button("Unlock set for editing") {
                    guard let target = editTarget else { return }
                    editingSetID = target.setID
                    store.toggleSessionSetLogged(on: day, exerciseID: target.exerciseID, setID: target.setID)
                    editTarget = nil
                }
                Button("Keep logged set", role: .cancel) { editTarget = nil }
            } message: { Text("This removes its logged entry. Your values remain in the draft; log it again after editing.") }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { inputFocused = false }
                }
            }
        }
    }

    private func sessionHeader(_ session: ActiveWorkoutSession) -> some View {
        VStack(spacing: 16) {
            HStack {
                Button { inputFocused = false; dismiss() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                    .accessibilityLabel("Collapse workout, keep session running")
                Text(session.workoutName).font(.community(.headline))
                Spacer(minLength: 8)
                Button("Finish", action: onFinish).font(.community(.subheadline, weight: .bold)).foregroundStyle(phase.accent)
                    .disabled(store.isSaving || store.hasPendingSetChanges)
            }.buttonStyle(.plain)
            HStack {
                Label { Text(session.startedAt, style: .timer).monospacedDigit() } icon: {
                    Image(systemName: "stopwatch").foregroundStyle(phase.accent)
                }.font(.community(.title2, weight: .bold))
                Spacer()
                Text("\(session.loggedSetCount) / \(session.totalSetCount) sets logged")
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
            }
            ProgressView(value: Double(session.loggedSetCount), total: Double(max(session.totalSetCount, 1)))
                .tint(phase.accent)
        }
    }

    private func setEditor(_ set: WorkoutSetDraft, exercise: SessionExerciseDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Set \(set.setNumber) of \(exercise.sets.count)").font(.community(.headline))
                Spacer()
                Text("YOUR NEXT SET").font(.community(.caption2, weight: .bold)).foregroundStyle(phase.accent)
            }
            inputLayout {
                numberField("Weight · \(weightUnit.label)", value: Binding(
                    get: { weightInputs[set.id] ?? weightUnit.display(kilograms: currentSet(exercise.id, set.id)?.weightKilograms ?? "") },
                    set: {
                        weightInputs[set.id] = $0
                        store.updateSessionSet(on: day, exerciseID: exercise.id, setID: set.id, weightKilograms: weightUnit.kilograms(display: $0))
                    }
                ), keyboard: .decimalPad)
                numberField("Reps", value: Binding(
                    get: { currentSet(exercise.id, set.id)?.reps ?? "" },
                    set: { store.updateSessionSet(on: day, exerciseID: exercise.id, setID: set.id, reps: $0) }
                ), keyboard: .numberPad)
            }
            Button {
                inputFocused = false
                store.toggleSessionSetLogged(on: day, exerciseID: exercise.id, setID: set.id)
            } label: {
                HStack {
                    if store.isSetPending(set.id) { ProgressView() }
                    Text(store.isSetPending(set.id) ? "Saving set…" : "Log set \(set.setNumber)")
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }.buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
                .disabled(!set.canBeLogged || store.isSetPending(set.id) || store.isSaving)
            Text("Weight is optional for bodyweight exercises. Enter reps to log.")
                .font(.community(.caption)).foregroundStyle(phase.secondaryText)
            if !set.isWeightValid || (!set.reps.isEmpty && !set.areRepsValid) {
                Text("Enter a valid weight and a whole number of reps.").font(.community(.caption)).foregroundStyle(.red)
            }
        }
        .padding(16).workoutOutline(radius: 20)
        .disabled(store.isSetPending(set.id) || !unitLoaded)
    }

    private func numberField(_ title: String, value: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.community(.caption)).foregroundStyle(phase.secondaryText)
            TextField(title == "Reps" ? "Reps" : "Optional", text: value)
                .font(.community(.title, weight: .bold)).keyboardType(keyboard).focused($inputFocused)
                .accessibilityLabel(title)
        }.padding(14).frame(maxWidth: .infinity, minHeight: 94, alignment: .leading).workoutOutline()
    }

    private var inputLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private func history(_ exercise: SessionExerciseDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This exercise").font(.community(.headline))
                Spacer()
                Text("\(exercise.sets.filter(\.isLogged).count) of \(exercise.sets.count) logged")
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
            }
            ForEach(exercise.sets.filter { $0.isLogged }) { set in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(RepbaseDesign.success)
                    Text("Set \(set.setNumber)").font(.community(.subheadline, weight: .bold))
                    Text((set.weightKilograms.isEmpty ? "Bodyweight" : "\(weightUnit.display(kilograms: set.weightKilograms)) \(weightUnit.label)") + " × \(set.reps)")
                        .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                    Spacer(minLength: 0)
                    Button("Edit") { editTarget = SetEditTarget(exerciseID: exercise.id, setID: set.id) }
                        .font(.community(.caption, weight: .bold)).frame(minHeight: 44)
                        .disabled(store.hasPendingSetChanges)
                }
            }
            if let upcoming = exercise.sets.filter({ !$0.isLogged }).dropFirst().first {
                Label("Set \(upcoming.setNumber) · Up next", systemImage: "circle")
                    .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
            }
            Button { store.addSessionSet(on: day, exerciseID: exercise.id) } label: {
                Label("Add a set", systemImage: "plus").frame(minHeight: 44)
            }.font(.community(.caption)).disabled(store.hasPendingSetChanges || store.isSaving)
        }
    }

    private func currentSet(_ exerciseID: UUID, _ setID: UUID) -> WorkoutSetDraft? {
        session?.exercises.first { $0.id == exerciseID }?.sets.first { $0.id == setID }
    }

    private func switchTo(_ id: UUID) {
        guard !store.hasPendingSetChanges else { return }
        inputFocused = false
        selectedExerciseID = id
        switching = false
    }

    private func switcher(_ session: ActiveWorkoutSession) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bench taken? Keep moving.\nCome back whenever you’re ready.")
                        .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
                    ForEach(session.exercises) { exercise in
                        let current = exercise.id == selectedExerciseID
                        let logged = exercise.sets.filter(\.isLogged).count
                        Button { switchTo(exercise.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(exercise.name).font(.community(.headline))
                                Text("\(logged) of \(exercise.sets.count) sets logged" + (current ? " · Current exercise" : logged == exercise.sets.count ? " · Complete" : logged == 0 ? " · Not started" : " · In progress"))
                                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                                Text(current ? "Keep going here" : "Switch to this exercise →")
                                    .font(.community(.subheadline, weight: .bold)).foregroundStyle(phase.accent)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).workoutOutline(selected: current, radius: 16)
                        }.buttonStyle(.plain).disabled(store.hasPendingSetChanges)
                            .accessibilityAddTraits(current ? [.isSelected] : [])
                    }
                    Text("Switching won’t complete or reset your sets.")
                        .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                }.padding(24)
            }
            .navigationTitle("Jump to exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { switching = false } } }
            .repbaseScreen(.focus)
        }
    }
}

struct WorkoutCompletionSummary: View {
    let completed: CompletedWorkoutSession
    let onDone: () -> Void
    private let phase = WorkoutVisualPhase.recover
    private var session: ActiveWorkoutSession { completed.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Workout complete").font(.community(.headline))
                Spacer()
                Button("Done", action: onDone).foregroundStyle(phase.accent)
            }
            Image(systemName: "checkmark.seal.fill").font(.system(size: 42)).foregroundStyle(phase.accent)
            Text("You showed up.\nThat counts.").font(.community(.largeTitle, weight: .bold))
            Text("\(session.workoutName) · \(session.startedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.community(.subheadline)).foregroundStyle(phase.secondaryText)
            HStack(spacing: 12) {
                metric("Workout time", duration)
                metric("Sets logged", "\(session.loggedSetCount) / \(session.totalSetCount)")
            }
            Text("Your effort, logged.").font(.community(.title3, weight: .bold))
            ForEach(session.exercises) { exercise in
                let count = exercise.sets.filter(\.isLogged).count
                HStack(spacing: 12) {
                    Image(systemName: count == exercise.sets.count && count > 0 ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                        .foregroundStyle(count == exercise.sets.count && count > 0 ? RepbaseDesign.success : phase.secondaryText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name).font(.community(.headline))
                        Text("\(count) of \(exercise.sets.count) sets logged").font(.community(.caption)).foregroundStyle(phase.secondaryText)
                    }
                }
            }
            Label("Workout saved to your history.", systemImage: "checkmark")
                .font(.community(.caption)).foregroundStyle(phase.secondaryText)
            Button(action: onDone) {
                HStack { Text("Back to workouts"); Spacer(); Image(systemName: "arrow.right") }
            }.buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
        }
    }

    private var duration: String {
        let seconds = max(0, Int(completed.endedAt.timeIntervalSince(session.startedAt)))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.community(.title2, weight: .bold)).monospacedDigit()
            Text(title).font(.community(.caption)).foregroundStyle(phase.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).workoutOutline(radius: 16)
    }
}
