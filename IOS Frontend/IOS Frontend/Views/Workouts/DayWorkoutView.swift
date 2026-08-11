//
//  DayWorkoutView.swift
//  IOS Frontend
//
//  Planning and live logging workspace for one selected day.
//

import SwiftUI

struct DayWorkoutView: View {
    let day: Weekday

    @Environment(WorkoutStore.self) private var store
    @State private var setupDraft = Workout(name: "", exercises: [])
    @State private var editor: WorkoutEditorView.Mode?
    @State private var showingRemoveConfirmation = false
    @State private var showingEndConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var completionNotice: String?

    private var workout: Workout? {
        store.workout(on: day)
    }

    private var activeSession: ActiveWorkoutSession? {
        store.activeSession(on: day)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dayHeader

                if let persistenceError = store.persistenceError {
                    persistenceErrorCard(persistenceError)
                }

                if let completionNotice {
                    completionCard(completionNotice)
                }

                if let activeSession {
                    activeSessionWorkspace(activeSession)
                } else if let workout {
                    plannedWorkout(workout)
                } else {
                    emptyDaySetup
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(day.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor) { mode in
            WorkoutEditorView(mode: mode) { savedWorkout in
                store.saveWorkout(savedWorkout, on: day)
            }
        }
        .confirmationDialog(
            "Remove \(workout?.name ?? "this workout")?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from \(day.fullName)", role: .destructive) {
                store.removeWorkout(on: day)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You can create a new plan for this day at any time.")
        }
        .confirmationDialog(
            "Finish this workout?",
            isPresented: $showingEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Session") {
                Task {
                    if let count = await store.endSession(on: day) {
                        completionNotice = "Workout complete - \(count) set\(count == 1 ? "" : "s") logged."
                    }
                }
            }
            Button("Keep Training", role: .cancel) { }
        } message: {
            Text("Your logged sets and completed session will be saved to Repbase.")
        }
        .confirmationDialog(
            "Discard this session?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Session", role: .destructive) {
                Task {
                    await store.discardSession(on: day)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Weight and rep entries from this session will be lost.")
        }
        .overlay {
            if store.isSaving {
                ZStack {
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                    ProgressView("Saving to Repbase...")
                        .padding(18)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                }
            }
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 14) {
            VStack(spacing: 1) {
                Text(day.shortName.uppercased())
                    .font(.caption.weight(.bold))
                Image(systemName: headerIcon)
                    .font(.title2)
            }
            .foregroundStyle(Color.white)
            .frame(width: 58, height: 58)
            .background(headerColor, in: RoundedRectangle(cornerRadius: 17))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(headerEyebrow)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(headerColor)
                    if store.today == day {
                        Text("TODAY")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }

                Text(workout?.name ?? "No workout assigned")
                    .font(.title3.weight(.bold))
                Text(headerDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .workoutCard()
    }

    private var emptyDaySetup: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Build \(day.fullName)'s Workout")
                    .font(.title2.weight(.bold))
                Text("Name your workout, add exercises, and choose the target number of sets.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            WorkoutPlanFields(draft: $setupDraft)

            Button {
                saveSetupDraft()
            } label: {
                Label("Save to \(day.fullName)", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSaveSetup || !store.isEditingEnabled)

            Text("This creates a reusable workout template and assigns it to this date in Repbase.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

    private func plannedWorkout(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("READY WHEN YOU ARE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                        Text(workout.name)
                            .font(.title2.weight(.bold))
                    }
                    Spacer()
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }

                HStack(spacing: 10) {
                    PlanStat(value: workout.exercises.count, label: "Exercises")
                    PlanStat(value: workout.totalSets, label: "Target Sets")
                }

                sessionStartControl(for: workout)
            }
            .workoutCard()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Workout Plan")
                        .font(.headline)
                    Spacer()
                    Button("Edit") {
                        editor = .edit(workout)
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(!store.isEditingEnabled)
                }

                if workout.exercises.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        Text("Add at least one exercise before starting.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Add Exercises") {
                            editor = .edit(workout)
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .workoutCard()
                } else {
                    ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                        PlannedExerciseRow(position: index + 1, exercise: exercise)
                    }
                }
            }

            Button(role: .destructive) {
                showingRemoveConfirmation = true
            } label: {
                Label("Remove Workout from \(day.fullName)", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!store.isEditingEnabled)
        }
    }

    @ViewBuilder
    private func sessionStartControl(for workout: Workout) -> some View {
        if let otherSession = store.activeSession, otherSession.day != day {
            VStack(alignment: .leading, spacing: 10) {
                Label("A workout is already active on \(otherSession.day.fullName).", systemImage: "bolt.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
                NavigationLink {
                    DayWorkoutView(day: otherSession.day)
                } label: {
                    Label("Continue \(otherSession.workoutName)", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.orange)
            }
        } else {
            Button {
                completionNotice = nil
                store.startSession(on: day)
            } label: {
                Label("Start Session", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(workout.exercises.isEmpty || !store.isEditingEnabled)
        }
    }

    private func activeSessionWorkspace(_ session: ActiveWorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("SESSION IN PROGRESS", systemImage: "bolt.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.green)
                        Text(session.workoutName)
                            .font(.title2.weight(.bold))
                    }
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsedTime(from: session.startedAt, to: context.date))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Color.green)
                    }
                }

                ProgressView(
                    value: Double(session.loggedSetCount),
                    total: Double(max(session.totalSetCount, 1))
                )
                .tint(Color.green)

                Text("\(session.loggedSetCount) of \(session.totalSetCount) sets logged")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .workoutCard()

            VStack(alignment: .leading, spacing: 4) {
                Text("Log Your Sets")
                    .font(.title3.weight(.bold))
                Text("Enter reps and optional weight, then tap the checkmark.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(session.exercises) { exercise in
                sessionExerciseCard(exercise)
            }

            Button {
                showingEndConfirmation = true
            } label: {
                Label("End Session", systemImage: "flag.checkered")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.green)
            .disabled(store.isSaving || store.hasPendingSetChanges)

            Button(role: .destructive) {
                showingDiscardConfirmation = true
            } label: {
                Text("Discard Session")
                    .frame(maxWidth: .infinity)
            }
            .disabled(store.isSaving || store.hasPendingSetChanges)
        }
    }

    private func sessionExerciseCard(_ exercise: SessionExerciseDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(exercise.name)
                    .font(.headline)
                Spacer()
                Text("\(exercise.sets.filter(\.isLogged).count)/\(exercise.sets.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 8) {
                Text("SET")
                    .frame(width: 34)
                Text("WEIGHT (KG)")
                    .frame(maxWidth: .infinity)
                Text("REPS")
                    .frame(maxWidth: .infinity)
                Text("LOG")
                    .frame(width: 40)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)

            ForEach(exercise.sets) { set in
                HStack(spacing: 8) {
                    Text("\(set.setNumber)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(width: 34)

                    TextField("0", text: weightBinding(exerciseID: exercise.id, setID: set.id))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.red.opacity(set.isWeightValid ? 0 : 0.8), lineWidth: 1)
                        }
                        .disabled(set.isLogged)
                        .accessibilityLabel("Set \(set.setNumber) weight in kilograms")

                    TextField("0", text: repsBinding(exerciseID: exercise.id, setID: set.id))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.red.opacity(set.areRepsValid || set.reps.isEmpty ? 0 : 0.8), lineWidth: 1)
                        }
                        .disabled(set.isLogged)
                        .accessibilityLabel("Set \(set.setNumber) repetitions")

                    Button {
                        store.toggleSessionSetLogged(on: day, exerciseID: exercise.id, setID: set.id)
                    } label: {
                        Group {
                            if store.isSetPending(set.id) {
                                ProgressView()
                            } else {
                                Image(systemName: set.isLogged ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(set.isLogged ? Color.green : Color.secondary)
                            }
                        }
                        .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        store.isSetPending(set.id)
                            || (!set.isLogged && !set.canBeLogged)
                    )
                    .accessibilityLabel(set.isLogged ? "Mark set \(set.setNumber) incomplete" : "Log set \(set.setNumber)")
                }
            }

            Divider()

            HStack {
                Button {
                    store.addSessionSet(on: day, exerciseID: exercise.id)
                } label: {
                    Label("Add Set", systemImage: "plus")
                }

                Spacer()

                Button {
                    store.removeLastSessionSet(on: day, exerciseID: exercise.id)
                } label: {
                    Label("Remove Last", systemImage: "minus")
                }
                .disabled(
                    exercise.sets.count <= 1
                        || exercise.sets.last.map(store.isSetPending) == true
                )
            }
            .font(.subheadline.weight(.semibold))
        }
        .workoutCard()
    }

    private var canSaveSetup: Bool {
        !setupDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var headerIcon: String {
        if activeSession != nil { return "bolt.fill" }
        return workout == nil ? "plus" : "figure.strengthtraining.traditional"
    }

    private var headerColor: Color {
        activeSession == nil ? Color.accentColor : Color.green
    }

    private var headerEyebrow: String {
        if activeSession != nil { return "ACTIVE WORKOUT" }
        return workout == nil ? "PLAN YOUR DAY" : "WORKOUT PLAN"
    }

    private var headerDescription: String {
        if let session = activeSession {
            return "\(session.loggedSetCount) of \(session.totalSetCount) sets logged"
        }
        if let workout {
            return "\(workout.exercises.count) exercises | \(workout.totalSets) target sets"
        }
        return "Build it exactly the way you want."
    }

    private func saveSetupDraft() {
        var workout = setupDraft
        workout.name = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        workout.exercises = workout.exercises.compactMap { exercise in
            var exercise = exercise
            exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return exercise.name.isEmpty ? nil : exercise
        }
        guard !workout.name.isEmpty else { return }
        store.saveWorkout(workout, on: day)
    }

    private func weightBinding(exerciseID: Exercise.ID, setID: WorkoutSetDraft.ID) -> Binding<String> {
        Binding(
            get: { sessionSet(exerciseID: exerciseID, setID: setID)?.weightKilograms ?? "" },
            set: { store.updateSessionSet(on: day, exerciseID: exerciseID, setID: setID, weightKilograms: $0) }
        )
    }

    private func repsBinding(exerciseID: Exercise.ID, setID: WorkoutSetDraft.ID) -> Binding<String> {
        Binding(
            get: { sessionSet(exerciseID: exerciseID, setID: setID)?.reps ?? "" },
            set: { store.updateSessionSet(on: day, exerciseID: exerciseID, setID: setID, reps: $0) }
        )
    }

    private func sessionSet(exerciseID: Exercise.ID, setID: WorkoutSetDraft.ID) -> WorkoutSetDraft? {
        store.activeSession(on: day)?
            .exercises.first(where: { $0.id == exerciseID })?
            .sets.first(where: { $0.id == setID })
    }

    private func elapsedTime(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func persistenceErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Color.orange)
            Button("Retry") { store.retryPersistence() }
                .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private func completionCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.green)
            Text(message)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                completionNotice = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PlanStat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PlannedExerciseRow: View {
    let position: Int
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            Text(exercise.name)
                .font(.body.weight(.medium))
            Spacer()
            Text("\(exercise.sets) set\(exercise.sets == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .workoutCard()
    }
}

#Preview("Empty Day") {
    NavigationStack {
        DayWorkoutView(day: .wednesday)
    }
    .environment(WorkoutStore())
}

#Preview("Scheduled Day") {
    NavigationStack {
        DayWorkoutView(day: .monday)
    }
    .environment(WorkoutStore.preview)
}
