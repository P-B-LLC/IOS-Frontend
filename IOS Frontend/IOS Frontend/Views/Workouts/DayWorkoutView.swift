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
    @Environment(GearStore.self) private var gearStore
    @State private var setupDraft = Workout(name: "", exercises: [])
    @State private var editor: WorkoutEditorView.Mode?
    /// The workout awaiting a delete confirmation, if any.
    /// Which workout page is on screen when a day holds several.
    @State private var visibleWorkoutID: Workout.ID?
    @State private var completedSession: CompletedWorkoutSession?
    /// The finished session being shared, if the summary's Share was tapped.
    @State private var sharedWorkout: SharedPostSource?
    /// Set when Finish was tapped on a session that logged nothing.
    @State private var isConfirmingEmptyFinish = false
    /// Gear chosen before the session exists, applied once it does.
    @State private var pendingGearID: Int?

    private var workout: Workout? {
        store.workout(on: day)
    }

    private var plannedWorkouts: [Workout] {
        store.workouts(on: day)
    }

    private var activeSession: ActiveWorkoutSession? {
        store.activeSession(on: day)
    }

    private var visualPhase: WorkoutVisualPhase {
        if completedSession != nil { return .recover }
        if activeSession != nil { return .focus }
        return .prepare
    }

    var body: some View {
        styledContent
        .task {
            // Only when nothing has been read yet. The dashboard loads the
            // same history, so arriving from the workouts page already has it,
            // and refetching every finished session on every visit to a day
            // would be a heavy read for a badge.
            if store.dashboardSessions.isEmpty {
                await store.loadDashboardSessions()
            }
        }
        .onChange(of: activeSession?.loggedSetCount ?? 0) { _, logged in
            // Logging a set answers the notice, so it stops being true and
            // goes. Leaving it up would have the page insisting nothing is
            // logged directly above a row that plainly is.
            if logged > 0, isConfirmingEmptyFinish {
                withAnimation(.easeOut(duration: 0.2)) {
                    isConfirmingEmptyFinish = false
                }
            }
        }
        .onChange(of: activeSession?.serverID) { _, started in
            // The session those shoes were picked for has just been created,
            // so the choice made before Start can finally be attached to it.
            guard let started, let chosen = pendingGearID else { return }
            pendingGearID = nil
            Task {
                await gearStore.assign(
                    gearStore.gear(withID: chosen),
                    toSession: started
                )
            }
        }
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
            WorkoutEditorView(
                mode: mode,
                suggestions: store.knownWorkouts
            ) { savedWorkout in
                store.saveWorkout(savedWorkout, on: day)
            }
        }
        .sheet(item: $sharedWorkout) { shared in
            NavigationStack {
                PostComposerView(
                    kind: .workout,
                    sourceID: shared.id,
                    subject: completedSession?.session.workoutName ?? "Workout"
                )
            }
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

    /// The scrolling page with its appearance applied.
    ///
    /// Kept apart from the sheets and dialogs in `body`: as one chain the
    /// type-checker could no longer resolve the expression.
    private var styledContent: some View {
        ScrollView {
            content
                .padding(.horizontal)
                .padding(.vertical, 12)
                // Pushed inside the tab, so the bottom bar sits over it exactly
                // as it does over the tab's own page. Without this the last row
                // -- Remove, or the repeat toggle -- cannot be scrolled clear
                // of the bar.
                .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .repbaseScreen(visualPhase)
        .toolbar(visualPhase == .prepare ? .visible : .hidden, for: .navigationBar)
        .navigationTitle(day.fullName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Split out of `body` because the type-checker could not resolve the two
    /// together once the session summary grew.
    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let completedSession {
                recoveryWorkspace(completedSession)
            } else {
                if activeSession == nil {
                    dayHeader
                }

                if let persistenceError = store.persistenceError {
                    persistenceErrorCard(persistenceError)
                }

                if let activeSession {
                    activeSessionWorkspace(activeSession)
                } else if !plannedWorkouts.isEmpty {
                    plannedDay
                } else {
                    emptyDaySetup
                }
            }
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 14) {
            VStack(spacing: 1) {
                Text(day.shortName.uppercased())
                    .font(.caption.weight(.bold))
                if let workout {
                    WorkoutInkArtwork(type: workout.type, size: 31, color: .white)
                } else {
                    Image(systemName: headerIcon)
                        .font(.title2)
                }
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
                            .foregroundStyle(WorkoutVisualPhase.prepare.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(WorkoutVisualPhase.prepare.accent.opacity(0.12), in: Capsule())
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
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("NO WORKOUT PLANNED")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(WorkoutVisualPhase.prepare.accent)
                Text("Choose how you want to train.")
                    .font(.title2.weight(.bold))
                Text("Reuse a plan to keep its history, or start fresh.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            WorkoutPlanFields(
                draft: $setupDraft,
                suggestions: store.knownWorkouts,
                sections: .identity
            )

            Button {
                editor = .build(setupDraft)
            } label: {
                Label("Build Custom Workout", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkoutPrimaryButtonStyle(phase: .prepare))
            .disabled(!canSaveSetup || !store.isEditingEnabled)

            if !canSaveSetup && store.isEditingEnabled {
                Text("Choose a previously used workout or give this one a name to continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
            }
        }
    }

    private var canSaveSetup: Bool {
        !setupDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Finishes the session, asking first only when it recorded nothing.
    ///
    /// Every other destructive action in this app acts on the first tap, on
    /// the user's instruction, and finishing normally still does. This one case
    /// is not a confirmation of intent but a correction of a likely mistake:
    /// typing into the boxes does not log a set, tapping the circle does, and
    /// three sessions on this account were finished holding nothing at all.
    private func endSession() {
        // Only a workout with sets can be empty in this sense. A run, ride or
        // swim logs none at all, so its `loggedSetCount` is always zero, and
        // this guard used to stop every one of them from ever being finished:
        // both Finish and End Session raised a notice that is only drawn on
        // the lifting layout, so nothing appeared and nothing happened. The
        // condition is deliberately the same one that decides whether the
        // notice is on screen — refusing to act while saying nothing is worse
        // than not refusing at all.
        if let session = activeSession,
           session.tracksDistance == false,
           session.loggedSetCount == 0 {
            withAnimation(.easeOut(duration: 0.2)) {
                isConfirmingEmptyFinish = true
            }
            return
        }
        // Logging a set after the notice appeared answers it, so it should not
        // still be sitting there.
        isConfirmingEmptyFinish = false
        finishSession()
    }

    /// Shown in the page instead of a system dialog when Finish is tapped with
    /// nothing logged.
    ///
    /// A modal was the wrong shape for this. It covered the very rows it was
    /// describing, so the instruction pointed at circles the user could no
    /// longer see, and a system alert looks like it belongs to a different app
    /// than the one around it. In the page, the sentence and the thing it is
    /// about are on screen together, and carrying on is the default rather
    /// than something to dismiss first.
    private func emptyFinishNotice(phase: WorkoutVisualPhase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: "circle.dashed")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(phase.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Nothing logged yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(phase.primaryText)
                    Text("Typing a weight or reps does not save the set. Tap Log at the end of a row to record it.")
                        .font(.caption)
                        .foregroundStyle(phase.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 14) {
                Button("Finish with no sets") {
                    isConfirmingEmptyFinish = false
                    finishSession()
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.red)

                Button("Keep logging") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isConfirmingEmptyFinish = false
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(phase.secondaryText)

                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            phase.accent.opacity(0.10),
            in: RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius)
                .strokeBorder(phase.accent.opacity(0.35), lineWidth: 1)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func finishSession() {
        Task {
            if await store.endSession(on: day) != nil {
                completedSession = store.completedSessions.last
            }
        }
    }

    /// Records set this session, judged by the backend against every set
    /// logged before it. Shown only when there is something to celebrate.
    private func personalRecordsSection(phase: WorkoutVisualPhase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "trophy.fill")
                    .font(.caption)
                    .foregroundStyle(phase.accent)
                Text("^[\(store.personalRecords.count) new personal record](inflect: true)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(phase.accent)
                Spacer(minLength: 0)
            }

            ForEach(store.personalRecords) { record in
                PersonalRecordRow(record: record, phase: phase)
            }
        }
        .padding(14)
        .background(
            phase.accent.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    /// Everything the backend measured from the track. A ride leads with speed
    /// and a run with pace, and the splits show how the effort was paced.
    private func routeSummarySection(
        _ summary: SessionRouteSummary,
        phase: WorkoutVisualPhase
    ) -> some View {
        let isRide = completedSession?.session.workoutType == .biking
        let slowest = summary.splits.compactMap(\.paceSecondsPerKilometer).max()

        return VStack(alignment: .leading, spacing: 12) {
            Text("ROUTE SUMMARY")
                .font(.caption2.weight(.bold))
                .foregroundStyle(phase.secondaryText)

            HStack(spacing: 10) {
                if let distance = summary.distanceText {
                    RouteStat(
                        title: "Distance",
                        value: distance,
                        icon: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }
                if isRide, let speed = summary.averageSpeedText {
                    RouteStat(title: "Avg speed", value: speed, icon: "speedometer")
                } else if let pace = summary.movingPaceText ?? summary.paceText {
                    RouteStat(title: "Moving pace", value: pace, icon: "speedometer")
                }
            }

            HStack(spacing: 10) {
                if let top = summary.maxSpeedText {
                    RouteStat(title: "Top speed", value: top, icon: "bolt.fill")
                }
                if let climb = summary.elevationGainText {
                    RouteStat(title: "Climb", value: climb, icon: "mountain.2.fill")
                } else if !isRide, let elapsed = summary.paceText {
                    RouteStat(title: "Overall pace", value: elapsed, icon: "clock")
                }
            }

            if !summary.splits.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("SPLITS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(phase.secondaryText)

                    ForEach(summary.splits) { split in
                        SplitRow(
                            split: split,
                            slowestPace: slowest,
                            accent: phase.accent,
                            secondary: phase.secondaryText
                        )
                    }

                    Text("Each bar is one mile — shorter is faster. Even bars mean an evenly paced effort.")
                        .font(.caption2)
                        .foregroundStyle(phase.secondaryText)
                }
            }
        }
    }

    private func plannedWorkout(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                sessionOverview(for: workout)
                sessionStartControl(for: workout)
            }

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
                            .foregroundStyle(WorkoutVisualPhase.prepare.accent)
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
                        if index < workout.exercises.count - 1 {
                            Divider()
                        }
                    }
                }
            }

            // The finisher sits at the end of the workout it belongs to, not
            // as another workout in the day.
            if let machine = workout.cardioMachine {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AFTER YOUR LAST SET")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(WorkoutVisualPhase.prepare.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cardio finisher")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(machine.title)
                            .font(.headline)
                        Text(
                            workout.cardioTargetMinutes
                                .map { "\($0) min target · start it after your last set" }
                                ?? "Start it after your last set"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        WorkoutVisualPhase.prepare.surfaceStart,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(WorkoutVisualPhase.prepare.secondaryText.opacity(0.22))
                    }
                }
            }

            repeatToggle(for: workout)

            // Acts straight away. The button says exactly what it does, and it
            // only unschedules: the workout itself is kept and can be put back
            // on any day.
            Button(role: .destructive) {
                store.removeWorkout(workout, on: day)
            } label: {
                Text("Remove \(workout.name)")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.red)
            .padding(.vertical, 4)
            .disabled(!store.isEditingEnabled)
        }
    }

    private func sessionOverview(for workout: Workout) -> some View {
        HStack(spacing: 14) {
            WorkoutInkArtwork(
                type: workout.type,
                size: 48,
                color: WorkoutVisualPhase.prepare.primaryText
            )
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.type.sessionTitle)
                    .font(.title3.weight(.bold))
                Text(planDescription(for: workout))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WorkoutVisualPhase.prepare.accent)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }

    private func planDescription(for workout: Workout) -> String {
        let exercise = workout.exercises.count == 1 ? "exercise" : "exercises"
        let set = workout.totalSets == 1 ? "target set" : "target sets"
        return "\(workout.exercises.count) \(exercise) · \(workout.totalSets) \(set)"
    }

    /// Keeps a workout on this weekday in the weeks ahead.
    ///
    /// Turning it off only clears weeks that have not arrived yet. This week
    /// stays as it is, and so does every week already trained, because those
    /// are a record of what happened rather than a plan.
    private func repeatToggle(for workout: Workout) -> some View {
        Toggle(
            isOn: Binding(
                get: { workout.repeatsWeekly },
                set: { store.setRepeat(workout, on: day, repeats: $0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Repeat every \(day.fullName)")
                    .font(.subheadline.weight(.semibold))
                Text(
                    workout.repeatsWeekly
                        ? "Keep this workout on future \(day.fullName)s."
                        : "Planned for this \(day.fullName) only."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .tint(RepbasePalette.charcoal)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .disabled(!store.isEditingEnabled || workout.serverID == nil)
    }

    /// Everything scheduled for the day. A single workout fills the page; when
    /// a day holds several, each gets its own page and the user swipes between
    /// them rather than scrolling past one to reach the next.
    private var plannedDay: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(plannedWorkouts.filter { store.isCompleted(workoutName: $0.name, on: dayDate) }) { done in
                completedBanner(done)
            }

            if plannedWorkouts.count > 1 {
                multiWorkoutBanner
                workoutPager
                pageIndicator
            } else if let only = plannedWorkouts.first {
                plannedWorkout(only)
            }

            Button {
                editor = .create
            } label: {
                HStack(spacing: 8) {
                    Text("Add another workout")
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 13)
            .overlay(alignment: .top) { Divider() }
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
                .foregroundStyle(WorkoutVisualPhase.prepare.accent)
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
            WorkoutVisualPhase.prepare.accent.opacity(0.1),
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
                            ? WorkoutVisualPhase.prepare.accent
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
                    HStack(spacing: 8) {
                        Text("Continue \(otherSession.workoutName)")
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WorkoutVisualPhase.focus.accent)
            }
        } else if store.isCompleted(workoutName: workout.name, on: dayDate) {
            // Nothing here. A finished day is started again through Redo
            // Session on its banner, which clears the day first: a second
            // Start beside the first would leave two records of one day, which
            // is what made six starts read as six workouts.
            EmptyView()
        } else {
            // Before Start, because this is when a runner knows what is on
            // their feet. There is no session to attach it to yet, so the
            // answer is held and applied the moment one exists.
            if workout.tracksDistance {
                GearPickerRow(
                    workoutType: workout.type,
                    destination: .pending($pendingGearID),
                    primaryText: WorkoutVisualPhase.prepare.primaryText,
                    secondaryText: WorkoutVisualPhase.prepare.secondaryText,
                    accent: WorkoutVisualPhase.prepare.accent
                )
            }

            Button {
                completedSession = nil
                // Ask before the session begins so tracking can start with the
                // first stride rather than after the prompt is answered.
                if workout.tracksDistance,
                   store.routeTracker.permission == .notDetermined {
                    store.routeTracker.requestPermission()
                }
                store.startSession(on: day, workoutID: workout.id)
            } label: {
                HStack(spacing: 8) {
                    Text("Start session")
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkoutPrimaryButtonStyle(phase: .prepare))
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
        let phase = WorkoutVisualPhase.focus

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button {
                    Task { await store.discardSession(on: day) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .tint(phase.primaryText)
                .accessibilityLabel("Discard session")

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(phase.onAccent)
                            .frame(width: 7, height: 7)
                        Text("LIVE  \(elapsedTime(from: session.startedAt, to: context.date))")
                            .font(.caption2.weight(.bold).monospacedDigit())
                    }
                    .foregroundStyle(phase.onAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(phase.accent, in: Capsule())
                    .shadow(color: phase.accent.opacity(0.30), radius: 12, y: 6)
                }

                Spacer()

                Button("Finish") {
                    endSession()
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(phase.primaryText)
                .foregroundStyle(phase.heroStart)
                .disabled(store.isSaving || store.hasPendingSetChanges)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("SESSION IN PROGRESS", systemImage: "bolt.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(RepbasePalette.sand)
                        Text(session.workoutName)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(phase.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                    }
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsedTime(from: session.startedAt, to: context.date))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(phase.accent)
                    }
                }

                ProgressView(
                    value: Double(session.loggedSetCount),
                    total: Double(max(session.totalSetCount, 1))
                )
                .tint(phase.accent)

                Text(
                    session.tracksDistance
                        ? "Timing your \(session.workoutType.title.lowercased()) — end the session to save it."
                        : "\(session.loggedSetCount) of \(session.totalSetCount) sets logged"
                )
                .font(.caption)
                .foregroundStyle(RepbasePalette.sand)
            }
            .padding(18)
            .background {
                WorkoutHeroBackground(phase: phase)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: phase.shadow, radius: 16, x: 5, y: 9)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            }

            if session.tracksDistance {
                // Above the map, because it is a decision to make now: the
                // miles are being run as this is on screen, and they land on
                // whichever shoe is named here.
                GearPickerRow(
                    workoutType: session.workoutType,
                    destination: .session(session.serverID),
                    primaryText: phase.primaryText,
                    secondaryText: phase.secondaryText,
                    accent: phase.accent
                )

                RouteTrackingCard(
                    tracker: store.routeTracker,
                    workoutType: session.workoutType
                )
            }

            // A run, ride, or swim needs nothing entered: GPS measures the
            // distance and the session measures the time. Only lifting has
            // sets to fill in.
            if !session.tracksDistance {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Log Your Sets")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(phase.primaryText)
                    Text(
                        store.previousSets.isEmpty
                            ? "Enter reps and optional weight, then tap Log to save each set."
                            : "Your last performance is already here. Enter today's values, then tap Log."
                    )
                        .font(.subheadline)
                        .foregroundStyle(phase.secondaryText)
                }

                if isConfirmingEmptyFinish {
                    emptyFinishNotice(phase: phase)
                }

                ForEach(session.exercises) { exercise in
                    sessionExerciseCard(exercise)
                }
            }

            Button {
                endSession()
            } label: {
                HStack(spacing: 8) {
                    Text("Finish workout")
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
            .disabled(store.isSaving || store.hasPendingSetChanges)

            Button(role: .destructive) {
                Task { await store.discardSession(on: day) }
            } label: {
                Text("Discard session")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.red.opacity(0.88))
            .padding(.vertical, 4)
            .disabled(store.isSaving || store.hasPendingSetChanges)
        }
        .foregroundStyle(phase.primaryText)
    }

    private func recoveryWorkspace(_ completed: CompletedWorkoutSession) -> some View {
        let phase = WorkoutVisualPhase.recover
        let session = completed.session
        let totalSets = max(session.totalSetCount, 1)
        let completionPercentage = Int(
            (Double(session.loggedSetCount) / Double(totalSets) * 100).rounded()
        )

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(phase.accent)
                    .frame(width: 40, height: 40)
                    .background(RepbasePalette.paper, in: Circle())

                Spacer()

                HStack(spacing: 7) {
                    Circle()
                        .fill(phase.accent)
                        .frame(width: 7, height: 7)
                    Text("COMPLETE")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(phase.accent)
                .padding(.horizontal, 18)
                .frame(height: 32)
                .background(phase.accent.opacity(0.10), in: Capsule())

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        sharedWorkout = SharedPostSource(id: session.serverID)
                    } label: {
                        Image(systemName: "arrow.up.right")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Share result")

                    Button("Done") { completedSession = nil }
                        .font(.caption.weight(.bold))
                        .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("WORKOUT COMPLETE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(phase.accent)
                Text("You showed up.")
                    .font(.largeTitle.weight(.bold))
                Text("\(session.workoutName) · \(dayDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                    .font(.subheadline)
                    .foregroundStyle(phase.secondaryText)
            }

            VStack(alignment: .leading, spacing: 11) {
                Text(session.workoutName.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(hex: 0xB7DCCB))

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(elapsedTime(from: session.startedAt, to: completed.endedAt))
                        .font(.system(.largeTitle, design: .default, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0xF3F7F5))
                    Text("WORKOUT TIME")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(hex: 0xB7DCCB))
                }

                Divider().overlay(Color(hex: 0x648474))

                HStack(spacing: 0) {
                    summaryDatum("START", session.startedAt.formatted(date: .omitted, time: .shortened))
                    summaryDatum("END", completed.endedAt.formatted(date: .omitted, time: .shortened))
                    summaryDatum("COMPLETE", "\(completionPercentage)%")
                }
            }
            .padding(18)
            .background {
                WorkoutHeroBackground(phase: phase)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: phase.shadow, radius: 14, x: 5, y: 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
            }

            // Above the figures, because the shape of where you went is the
            // thing worth seeing first, and the numbers describe it. Shown for
            // every run, ride and swim, including ones that recorded no track
            // at all: the map is part of what this page is, not a reward for
            // having had a GPS fix, and a page that changes shape depending on
            // the signal is harder to read than one that does not.
            // Again here, so forgetting to set it beforehand is not permanent.
            // The distance is already known by now, and attaching gear moves
            // it onto that shoe's total straight away.
            if session.tracksDistance {
                GearPickerRow(
                    workoutType: session.workoutType,
                    destination: .session(session.serverID),
                    primaryText: phase.primaryText,
                    secondaryText: phase.secondaryText,
                    accent: phase.accent
                )
            }

            if session.tracksDistance {
                SessionRouteMap(
                    points: store.completedRoute,
                    accent: phase.accent
                )
            }

            HStack {
                Text("SESSION HIGHLIGHTS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(phase.secondaryText)
                Spacer()
            }

            // A run is measured in distance, pace and climb. Sets and
            // completion belong to lifting and say nothing about a run.
            if session.tracksDistance {
                HStack(spacing: 10) {
                    RecoveryMetricCard(
                        title: "DISTANCE",
                        value: store.routeSummary?.distanceText
                            .map { $0.replacingOccurrences(of: " mi", with: "") } ?? "--",
                        detail: "MILES",
                        isEmphasized: true
                    )
                    RecoveryMetricCard(
                        title: session.workoutType == .biking ? "AVG SPEED" : "AVG PACE",
                        value: session.workoutType == .biking
                            ? (store.routeSummary?.averageSpeedText
                                .map { $0.replacingOccurrences(of: " mph", with: "") } ?? "--")
                            : (store.routeSummary?.movingPaceText
                                ?? store.routeSummary?.paceText)?
                                .replacingOccurrences(of: " /mi", with: "") ?? "--",
                        detail: session.workoutType == .biking ? "MPH" : "PER MILE",
                        isEmphasized: false
                    )
                    RecoveryMetricCard(
                        title: "CLIMB",
                        value: store.routeSummary?.elevationGainText
                            .map { $0.replacingOccurrences(of: " m", with: "") } ?? "0",
                        detail: "FEET",
                        isEmphasized: false
                    )
                }
            } else {
                HStack(spacing: 10) {
                    RecoveryMetricCard(
                        title: "SETS",
                        value: "\(session.loggedSetCount)",
                        detail: "OF \(session.totalSetCount) LOGGED",
                        isEmphasized: false
                    )
                    RecoveryMetricCard(
                        title: "EXERCISES",
                        value: "\(session.exercises.count)",
                        detail: "IN SESSION",
                        isEmphasized: false
                    )
                    RecoveryMetricCard(
                        title: "COMPLETION",
                        value: "\(completionPercentage)%",
                        detail: "FINISHED",
                        isEmphasized: true
                    )
                }
            }

            if session.tracksDistance, store.sessionHistory.count > 1 {
                SessionProgressChart(
                    history: store.sessionHistory,
                    workoutType: session.workoutType,
                    phase: phase
                )
            }

            // Offered after a lifting session, whether or not one was planned:
            // the finisher is the natural next step from this screen.
            if !session.tracksDistance {
                CardioFinisherCard(
                    plannedMachine: store.workout(on: day)?.cardioMachine,
                    sessionID: session.serverID,
                    phase: phase
                )
            }

            Button {
                sharedWorkout = SharedPostSource(id: session.serverID)
            } label: {
                HStack {
                    Text("Share result")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(phase.secondaryText)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) {
                Divider()
            }
            .accessibilityLabel("Share result to Feed")

            if !session.tracksDistance, !store.personalRecords.isEmpty {
                personalRecordsSection(phase: phase)
            }

            if !session.tracksDistance, !store.liftProgress.isEmpty {
                LiftProgressChart(series: store.liftProgress, phase: phase)
            }

            if !session.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("WHAT YOU LOGGED")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(RepbasePalette.caramel)
                        .padding(.bottom, 8)

                    ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exercise.name).font(.headline)
                                Text(loggedSetSummary(exercise))
                                    .font(.caption)
                                    .foregroundStyle(phase.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(phase.accent)
                        }
                        .padding(.vertical, 13)
                        if index < session.exercises.count - 1 { Divider() }
                    }
                }
            }

            if let persistenceError = store.persistenceError {
                persistenceErrorCard(persistenceError)
            }

            if let summary = store.routeSummary,
               summary.distanceText != nil || summary.paceText != nil {
                routeSummarySection(summary, phase: phase)
            }
        }
        .foregroundStyle(phase.primaryText)
        .task(id: session.serverID) {
            // Only a run, ride or swim has one to read, and asking for a
            // lifting session's track is a round trip that can only come back
            // empty.
            guard session.tracksDistance else { return }
            await store.loadCompletedRoute(sessionID: session.serverID)
        }
    }

    private func summaryDatum(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(hex: 0xB7DCCB))
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(hex: 0xF3F7F5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loggedSetSummary(_ exercise: SessionExerciseDraft) -> String {
        let logged = exercise.sets.filter(\.isLogged)
        guard !logged.isEmpty else { return "No sets logged" }
        return logged.map { set in
            let weight = set.weightKilograms.trimmingCharacters(in: .whitespacesAndNewlines)
            let reps = set.reps.trimmingCharacters(in: .whitespacesAndNewlines)
            if weight.isEmpty { return reps.isEmpty ? "Logged" : "\(reps) reps" }
            return reps.isEmpty ? "\(weight) kg" : "\(weight) × \(reps)"
        }.joined(separator: "  ·  ")
    }

    /// The date this day falls on, for asking whether it has been trained.
    private var dayDate: Date {
        store.workoutDate(for: day)
    }

    /// Says the day is done, and offers to take it back.
    ///
    /// The day counts once however many times it was started, so this is what
    /// tells the user which state they are in. Undo deletes the day's finished
    /// sessions, which is what removes it from the totals — nothing else marks
    /// a day complete, so there is no second place for the two to disagree.
    private func completedBanner(_ workout: Workout) -> some View {
        // The newest session for the day is the one shown. Older ones only
        // exist where a day was trained more than once before this screen
        // started refusing to start a finished day again.
        let session = store.finishedSessions(workoutName: workout.name, on: dayDate)
            .max { $0.performedAt < $1.performedAt }
        let overview = session.flatMap { store.sessionOverviews[$0.sessionID] }

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayDate.formatted(.dateTime.month(.wide).day()).uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(RepbasePalette.caramel)
                    Text(workout.name)
                        .font(.title.weight(.bold))
                    if let overview {
                        Text("Completed at \(overview.performedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Label("DONE", systemImage: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WorkoutVisualPhase.recover.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(WorkoutVisualPhase.recover.accent.opacity(0.10), in: Capsule())
            }

            if let overview {
                VStack(alignment: .leading, spacing: 14) {
                    Text("RECORDED SESSION")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(hex: 0xB7DCCB))
                    Text(workout.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color(hex: 0xF3F7F5))
                    Divider().overlay(Color(hex: 0x648474))
                    HStack(spacing: 0) {
                        historyMetric("\(overview.loggedSetCount)", "SETS")
                        historyMetric("\(overview.lines.count)", "EXERCISES")
                        historyMetric(overview.totalVolumeKilograms.map { "\($0.nutritionText) kg" } ?? "—", "VOLUME")
                    }
                }
                .padding(20)
                .background(WorkoutVisualPhase.recover.accent, in: RoundedRectangle(cornerRadius: 25, style: .continuous))

                Text("EXERCISES LOGGED")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(WorkoutVisualPhase.recover.accent)
                sessionOverviewLines(overview)
            } else if let session, store.loadingOverviewIDs.contains(session.sessionID) {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 9) {
                Button {
                    Task {
                        await store.redoSession(
                            workoutName: workout.name,
                            on: dayDate,
                            day: day,
                            workoutID: workout.id
                        )
                    }
                } label: {
                    Label("Repeat workout", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(RepbasePrimaryButtonStyle())
                .disabled(store.isSaving || !store.isEditingEnabled)

                Button("Undo") {
                    Task {
                        await store.undoCompletion(
                            workoutName: workout.name,
                            on: dayDate
                        )
                    }
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.bordered)
                .disabled(store.isSaving || !store.isEditingEnabled)

                Spacer(minLength: 0)
            }
        }
        .task(id: session?.sessionID) {
            guard let session else { return }
            await store.loadOverview(for: session)
        }
    }

    private func historyMetric(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color(hex: 0xF3F7F5))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(hex: 0xB7DCCB))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the day amounted to: when, how many sets, and how much was moved.
    private static func overviewSummary(_ overview: SessionOverview) -> String {
        var parts = [overview.performedAt.formatted(date: .abbreviated, time: .shortened)]
        parts.append("^[\(overview.loggedSetCount) set](inflect: true)")
        if let volume = overview.totalVolumeKilograms {
            parts.append("\(volume.nutritionText) kg moved")
        }
        return parts.joined(separator: "  ·  ")
    }

    /// Every exercise of the finished session with the sets as logged.
    private func sessionOverviewLines(_ overview: SessionOverview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(overview.lines.enumerated()), id: \.element.id) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%02d", index + 1))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(RepbasePalette.caramel)
                        .frame(width: 26, alignment: .leading)
                    Text(line.name)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(line.setsText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 12)
                if index < overview.lines.count - 1 { Divider() }
            }
        }
    }

    private func sessionExerciseCard(_ exercise: SessionExerciseDraft) -> some View {
        let phase = WorkoutVisualPhase.focus

        // Spelled out: a body with a statement before the view is no longer a
        // single expression, so Swift stops inferring the return.
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(.headline)
                        .foregroundStyle(phase.primaryText)
                    Text("\(exercise.sets.filter(\.isLogged).count) of \(exercise.sets.count) logged")
                        .font(.caption)
                        .foregroundStyle(phase.secondaryText)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Text("SET")
                    .frame(width: 34)
                Text("WEIGHT (KG)")
                    .frame(maxWidth: .infinity)
                Text("REPS")
                    .frame(maxWidth: .infinity)
                Text("LOG")
                    .frame(width: 62)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(phase.secondaryText)

            ForEach(exercise.sets) { set in
                // What this set was last time, so an empty field says "60 × 8"
                // rather than "0". Only a hint: it is never written in, because
                // what gets logged has to be what was lifted today.
                let last = store.previousSet(
                    exerciseServerID: exercise.exerciseServerID,
                    setNumber: set.setNumber
                )
                // Labelled, because a faded "100" in a weight box reads as a
                // value already entered rather than as last week's.
                let weightHint = last?.weightKilograms
                    .map { "Prev: \($0.nutritionText)" } ?? "0"
                let repsHint = last?.reps.map { "Prev: \($0)" } ?? "0"

                HStack(spacing: 8) {
                    Text("\(set.setNumber)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(phase.primaryText)
                        .frame(width: 34)

                    TextField(
                        "",
                        text: weightBinding(exerciseID: exercise.id, setID: set.id),
                        prompt: Text(weightHint).foregroundStyle(phase.secondaryText.opacity(0.72))
                    )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(phase.primaryText)
                        .tint(phase.accent)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            set.isLogged
                                ? RepbaseDesign.success.opacity(0.18)
                                : Color.white.opacity(0.065),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.red.opacity(set.isWeightValid ? 0 : 0.8), lineWidth: 1)
                        }
                        .disabled(set.isLogged)
                        .accessibilityLabel("Set \(set.setNumber) weight in kilograms")

                    TextField(
                        "",
                        text: repsBinding(exerciseID: exercise.id, setID: set.id),
                        prompt: Text(repsHint).foregroundStyle(phase.secondaryText.opacity(0.72))
                    )
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(phase.primaryText)
                        .tint(phase.accent)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            set.isLogged
                                ? RepbaseDesign.success.opacity(0.18)
                                : Color.white.opacity(0.065),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
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
                            } else if set.isLogged {
                                Label("Logged", systemImage: "checkmark")
                            } else {
                                Text("Log")
                            }
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(set.isLogged ? phase.onAccent : phase.primaryText)
                        .frame(width: 62, height: 38)
                        .background(
                            set.isLogged ? RepbaseDesign.success : Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    set.isLogged ? Color.clear : phase.secondaryText.opacity(0.3),
                                    lineWidth: 1
                                )
                        }
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
                .overlay(phase.secondaryText.opacity(0.22))

            HStack {
                Button {
                    store.addSessionSet(on: day, exerciseID: exercise.id)
                } label: {
                    Label("Add Set", systemImage: "plus")
                }
                .foregroundStyle(phase.primaryText)

                Spacer()

                Button {
                    store.removeLastSessionSet(on: day, exerciseID: exercise.id)
                } label: {
                    Label("Remove Last", systemImage: "minus")
                }
                .foregroundStyle(phase.secondaryText)
                .disabled(
                    exercise.sets.count <= 1
                        || exercise.sets.last.map {
                            store.isSetPending($0.id)
                        } == true
                )
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [phase.surfaceStart, phase.surfaceEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: phase.shadow.opacity(0.32), radius: 8, x: 0, y: 4)
    }

    private var headerIcon: String {
        if activeSession != nil { return "bolt.fill" }
        return workout == nil ? "plus" : "figure.strengthtraining.traditional"
    }

    private var headerColor: Color {
        activeSession == nil
            ? WorkoutVisualPhase.prepare.accent
            : WorkoutVisualPhase.focus.accent
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

}

private struct RecoveryMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let isEmphasized: Bool

    private let phase = WorkoutVisualPhase.recover

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(detail)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .foregroundStyle(
            isEmphasized ? phase.accent : phase.primaryText
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

/// One record, with the size of the jump over the previous best.
private struct PersonalRecordRow: View {
    let record: PersonalRecord
    let phase: WorkoutVisualPhase

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: record.isFirstEver ? "star.fill" : "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(phase.accent)
                .frame(width: 28, height: 28)
                .background(phase.accent.opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(record.exerciseName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(record.kind.title) · \(record.detailText)")
                    .font(.caption2)
                    .foregroundStyle(phase.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.valueText)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                if let improvement = record.improvementText {
                    Text(improvement)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(phase.accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(record.exerciseName), \(record.kind.title), \(record.valueText), \(record.detailText)"
        )
    }
}

/// One backend-computed route figure shown after a cardio session.
/// One mile split as a bar, so an uneven effort is visible at a glance.
private struct SplitRow: View {
    let split: SessionSplit
    let slowestPace: Double?
    let accent: Color
    let secondary: Color

    var body: some View {
        HStack(spacing: 9) {
            Text(label)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(secondary)
                .frame(width: 54, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.18))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(proxy.size.width * fraction, 6))
                }
            }
            .frame(height: 8)

            Text(SessionRouteSummary.durationText(split.seconds))
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 48, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(SessionRouteSummary.durationText(split.seconds))")
    }

    private var label: String {
        split.isPartial
            ? String(
                format: "mi %d (%.2f)",
                split.number,
                ImperialUnits.miles(fromKilometers: split.distanceKilometers)
              )
            : "mi \(split.number)"
    }

    /// Bars are scaled by pace, not raw time, so a partial final mile is
    /// compared fairly against the full ones.
    private var fraction: Double {
        guard let slowestPace, slowestPace > 0,
              let pace = split.paceSecondsPerKilometer else {
            return 1
        }
        return min(max(pace / slowestPace, 0.08), 1)
    }
}

private struct RouteStat: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(WorkoutVisualPhase.recover.accent)
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
        .background(
            WorkoutVisualPhase.recover.accent.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10)
        )
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
                .foregroundStyle(WorkoutVisualPhase.prepare.accent)
                .frame(width: 34, height: 34)
                .background(WorkoutVisualPhase.prepare.accent.opacity(0.12), in: Circle())
            Text(exercise.name)
                .font(.body.weight(.medium))
            Spacer()
            Text("\(exercise.sets) set\(exercise.sets == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
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
