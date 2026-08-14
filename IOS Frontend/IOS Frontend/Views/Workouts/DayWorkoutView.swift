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
    /// The workout awaiting a delete confirmation, if any.
    @State private var workoutPendingRemoval: Workout?
    /// Which workout page is on screen when a day holds several.
    @State private var visibleWorkoutID: Workout.ID?
    @State private var showingEndConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var completionNotice: String?

    private var workout: Workout? {
        store.workout(on: day)
    }

    private var plannedWorkouts: [Workout] {
        store.workouts(on: day)
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
                } else if !plannedWorkouts.isEmpty {
                    plannedDay
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
        .onChange(of: store.routeTracker.permission) {
            // Granting access part way through a session starts tracking for
            // the remainder of it.
            guard let session = activeSession,
                  session.tracksDistance,
                  store.routeTracker.permission.allowsTracking,
                  !store.routeTracker.isTracking else {
                return
            }
            store.routeTracker.startTracking()
        }
        .sheet(item: $editor) { mode in
            WorkoutEditorView(mode: mode) { savedWorkout in
                store.saveWorkout(savedWorkout, on: day)
            }
        }
        .confirmationDialog(
            "Remove \(workoutPendingRemoval?.name ?? "this workout")?",
            isPresented: Binding(
                get: { workoutPendingRemoval != nil },
                set: { if !$0 { workoutPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from \(day.fullName)", role: .destructive) {
                if let target = workoutPendingRemoval {
                    store.removeWorkout(target, on: day)
                }
                workoutPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { workoutPendingRemoval = nil }
        } message: {
            Text("This unschedules it from \(day.fullName). The workout itself is kept and can be scheduled again.")
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

            // A greyed-out button with no explanation reads as a broken app.
            if let reason = store.editingBlockedReason {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.orange)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if store.repositoryIsMissing {
                        Button("Retry") { store.retryPersistence() }
                            .font(.caption.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if !canSaveSetup {
                Text("Give this workout a name to save it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

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
                workoutPendingRemoval = workout
            } label: {
                Label("Remove \(workout.name) from \(day.fullName)", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!store.isEditingEnabled)
        }
    }

    /// Everything scheduled for the day. A single workout fills the page; when
    /// a day holds several, each gets its own page and the user swipes between
    /// them rather than scrolling past one to reach the next.
    private var plannedDay: some View {
        VStack(alignment: .leading, spacing: 18) {
            if plannedWorkouts.count > 1 {
                multiWorkoutBanner
                workoutPager
                pageIndicator
            } else if let only = plannedWorkouts.first {
                plannedWorkout(only)
            }

            Button {
                setupDraft = Workout(name: "", exercises: [])
                editor = .create
            } label: {
                Label("Add Another Workout to \(day.fullName)", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!store.isEditingEnabled)
        }
        .onAppear {
            if visibleWorkoutID == nil {
                visibleWorkoutID = plannedWorkouts.first?.id
            }
        }
    }

    private var multiWorkoutBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("^[\(plannedWorkouts.count) workout](inflect: true) planned")
                    .font(.subheadline.weight(.semibold))
                Text("Swipe to see the rest")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.compact.left")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            Color.accentColor.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    /// One page per workout. A horizontal scroll view nests cleanly inside the
    /// screen's vertical one, unlike a second vertical scroller would.
    private var workoutPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(Array(plannedWorkouts.enumerated()), id: \.element.id) { index, planned in
                    VStack(alignment: .leading, spacing: 14) {
                        Text("WORKOUT \(index + 1) OF \(plannedWorkouts.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        plannedWorkout(planned)
                        Spacer(minLength: 0)
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(planned.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $visibleWorkoutID)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(plannedWorkouts) { planned in
                Circle()
                    .fill(
                        planned.id == visibleWorkoutID
                            ? Color.accentColor
                            : Color.secondary.opacity(0.3)
                    )
                    .frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
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
                // Ask before the session begins so tracking can start with the
                // first stride rather than after the prompt is answered.
                if workout.tracksDistance,
                   store.routeTracker.permission == .notDetermined {
                    store.routeTracker.requestPermission()
                }
                store.startSession(on: day, workoutID: workout.id)
            } label: {
                Label("Start Session", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            // A run, ride, or swim needs no planned exercises to start.
            .disabled(
                (!workout.tracksDistance && workout.exercises.isEmpty)
                    || !store.isEditingEnabled
            )

            if let reason = store.editingBlockedReason {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.orange)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if store.repositoryIsMissing {
                        Button("Retry") { store.retryPersistence() }
                            .font(.caption.weight(.semibold))
                    }
                }
            } else if !workout.tracksDistance && workout.exercises.isEmpty {
                Text("Add at least one exercise to start this workout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

                Text(
                    session.tracksDistance
                        ? "Timing your \(session.workoutType.title.lowercased()) — end the session to save it."
                        : "\(session.loggedSetCount) of \(session.totalSetCount) sets logged"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .workoutCard()

            if session.tracksDistance {
                RouteTrackingCard(
                    tracker: store.routeTracker,
                    workoutType: session.workoutType
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.tracksDistance ? "Log Your Distance" : "Log Your Sets")
                    .font(.title3.weight(.bold))
                Text(
                    session.tracksDistance
                        ? "Enter how far you went, then tap the checkmark. Your time is recorded automatically."
                        : "Enter reps and optional weight, then tap the checkmark."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            ForEach(session.exercises) { exercise in
                if session.tracksDistance {
                    distanceEffortCard(exercise, type: session.workoutType)
                } else {
                    sessionExerciseCard(exercise)
                }
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

    /// Logging card for a run, ride, or swim: one distance entry. The elapsed
    /// time is the session's own, computed by the backend from start to end.
    private func distanceEffortCard(
        _ exercise: SessionExerciseDraft,
        type: WorkoutType
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(exercise.sets) { set in
                VStack(alignment: .leading, spacing: 10) {
                    Text(type.distanceTitle.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        TextField(
                            "0.0",
                            text: distanceBinding(exerciseID: exercise.id, setID: set.id)
                        )
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            Color.primary.opacity(0.045),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    Color.red.opacity(
                                        set.distanceKilometers.isEmpty || set.isDistanceValid ? 0 : 0.8
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .disabled(set.isLogged)
                        .accessibilityLabel("\(type.distanceTitle) in kilometers")

                        Text("km")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        Button {
                            store.toggleSessionSetLogged(
                                on: day,
                                exerciseID: exercise.id,
                                setID: set.id
                            )
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
                                || (!set.isLogged && !set.canBeLoggedAsDistance)
                        )
                        .accessibilityLabel(set.isLogged ? "Unlog distance" : "Log distance")
                    }
                }
            }
        }
        .workoutCard()
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
                        || exercise.sets.last.map {
                            store.isSetPending($0.id)
                        } == true
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
        let state: String
        if activeSession != nil {
            state = "ACTIVE WORKOUT"
        } else {
            state = workout == nil ? "PLAN YOUR DAY" : "WORKOUT PLAN"
        }
        return "\(state) | \(store.dateLabel(for: day).uppercased())"
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

    private func distanceBinding(
        exerciseID: Exercise.ID,
        setID: WorkoutSetDraft.ID
    ) -> Binding<String> {
        Binding(
            get: { sessionSet(exerciseID: exerciseID, setID: setID)?.distanceKilometers ?? "" },
            set: {
                store.updateSessionSet(
                    on: day,
                    exerciseID: exerciseID,
                    setID: setID,
                    distanceKilometers: $0
                )
            }
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
        VStack(alignment: .leading, spacing: 10) {
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

            // Distance and pace as the backend measured them from the track.
            if let summary = store.routeSummary,
               summary.distanceText != nil || summary.paceText != nil {
                HStack(spacing: 10) {
                    if let distance = summary.distanceText {
                        RouteStat(title: "Distance", value: distance, icon: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    if let pace = summary.paceText {
                        RouteStat(title: "Avg pace", value: pace, icon: "speedometer")
                    }
                }
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// One backend-computed route figure shown after a cardio session.
private struct RouteStat: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
