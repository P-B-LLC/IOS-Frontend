//
//  WorkoutStore.swift
//  IOS Frontend
//
//  Main-actor state backed by the generated Repbase API client.
//

import Foundation
import Observation

@Observable
final class WorkoutStore {
    private var repository: WorkoutAPIRepository?
    private var connectionGeneration = UUID()

    /// Current-week projection of concrete API WorkoutSchedule records. A date
    /// can hold more than one schedule, so each day maps to a list.
    private(set) var schedule: [Weekday: [Workout]]
    private(set) var persistenceError: String?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var activeSession: ActiveWorkoutSession?
    private(set) var completedSessions: [CompletedWorkoutSession] = []
    private(set) var pendingSetIDs: Set<WorkoutSetDraft.ID> = []
    /// Records the GPS track for cardio sessions.
    let routeTracker = RouteTracker()
    /// Distance and pace for the last finished route, as computed by the server.
    private(set) var routeSummary: SessionRouteSummary?
    /// The track of the finished session on screen, read back from the server.
    ///
    /// Fetched rather than kept from the recording, so a session opened from
    /// the history draws the same map as one that has only just been stopped.
    private(set) var completedRoute: [RoutePoint] = []
    /// Past finished runs of the same workout, oldest first, for the progress
    /// chart shown once a session ends.
    private(set) var sessionHistory: [SessionHistoryPoint] = []
    /// Records set by the session that just finished.
    private(set) var personalRecords: [PersonalRecord] = []
    /// How each exercise in the finished lifting session has progressed.
    private(set) var liftProgress: [LiftProgressSeries] = []
    /// Workouts the user has already created, offered when naming a new one so
    /// a workout's history is not split across two spellings.
    private(set) var knownWorkouts: [WorkoutSummary] = []
    /// Finished sessions the composer can offer. Read on demand rather than at
    /// connection: only that one screen needs them, and every other screen
    /// would pay for the pages on sign-in.
    private(set) var postableSessions: [PostableSession] = []
    private(set) var isLoadingPostableSessions = false
    /// What was lifted last time, by exercise id, for the session in progress.
    /// Read once when a session starts; empty when this workout has never been
    /// finished before, which is what a first session should show.
    private(set) var previousSets: [Int: [PreviousSet]] = [:]
    /// Completed sessions used by the training dashboard. These are loaded
    /// from the API and reduced into totals, streaks, and weekly trends by the
    /// view; the dashboard never fabricates progress values.
    private(set) var dashboardSessions: [PostableSession] = []
    /// Totals, streaks and the trend, counted by the server.
    ///
    /// These were worked out here, from every session ever recorded, which
    /// is why the history was paged in full on every visit to the dashboard.
    private(set) var trainingStats = TrainingStats.empty
    private(set) var isLoadingDashboardSessions = false

    // MARK: - Cardio finisher
    //
    // The cardio that follows a workout is timed after its session has ended,
    // then written onto that same session. It is part of the workout, not a
    // second one.

    /// Set while a finisher is being timed.
    private(set) var cardioStartedAt: Date?
    private(set) var cardioMachine: CardioMachine?
    /// The session the finisher will be recorded against.
    private var cardioSessionID: Int?
    /// Set once a finisher has been saved, so the summary can report it.
    private(set) var recordedCardioSeconds: Int?

    var isTimingCardio: Bool { cardioStartedAt != nil }

    init(initialSchedule: [Weekday: [Workout]] = [:]) {
        schedule = initialSchedule
    }

    // MARK: - Connection

    func connect(configuration: APIConfiguration, token: String) async {
        let generation = UUID()
        connectionGeneration = generation
        activeSession = nil
        pendingSetIDs = []
        // A fresh connection owns these flags; never inherit a stuck one.
        isLoading = false
        isSaving = false

        do {
            let repository = try WorkoutAPIRepository(
                configuration: configuration,
                token: token
            )
            self.repository = repository
            await reloadWeek(
                using: repository,
                generation: generation,
                showsLoadingState: true
            )
        } catch {
            self.repository = nil
            schedule = [:]
            persistenceError = error.localizedDescription
        }
    }

    func disconnect() {
        connectionGeneration = UUID()
        repository = nil
        schedule = [:]
        activeSession = nil
        pendingSetIDs = []
        persistenceError = nil
        isLoading = false
        isSaving = false
        // One user's workout names must never be offered to the next.
        knownWorkouts = []
        postableSessions = []
        previousSets = [:]
        sessionOverviews = [:]
        loadingOverviewIDs = []
        isLoadingPostableSessions = false
        dashboardSessions = []
        isLoadingDashboardSessions = false
        cardioStartedAt = nil
        cardioMachine = nil
        cardioSessionID = nil
        recordedCardioSeconds = nil
        sessionHistory = []
        personalRecords = []
        liftProgress = []
        routeSummary = nil
        completedRoute = []
    }

    // MARK: - Whether a day has been trained

    /// The finished sessions recorded for this workout on this date.
    ///
    /// Matched by name and calendar day, the same pair the dashboard counts
    /// by, so what a day says about itself and what the totals say cannot
    /// disagree.
    /// Sessions that recorded nothing are left out, so a day finished without
    /// a single set does not claim to be trained and does not close the day
    /// against starting it properly.
    func finishedSessions(workoutName: String, on date: Date) -> [PostableSession] {
        let day = Calendar.current.startOfDay(for: date)
        return dashboardSessions.filter {
            $0.recordedSomething
                && $0.workoutName.localizedCaseInsensitiveCompare(workoutName) == .orderedSame
                && Calendar.current.startOfDay(for: $0.performedAt) == day
        }
    }

    /// Whether this workout has been trained on this date at all.
    func isCompleted(workoutName: String, on date: Date) -> Bool {
        !finishedSessions(workoutName: workoutName, on: date).isEmpty
    }

    /// What was logged on a completed day, once it has been asked for.
    /// Keyed by session so opening one day does not clear another's.
    private(set) var sessionOverviews: [Int: SessionOverview] = [:]
    private(set) var loadingOverviewIDs: Set<Int> = []

    /// Reads back what a finished session recorded.
    ///
    /// Fetched only when a day is opened and asked to show itself, rather than
    /// with the rest of the history: the dashboard needs to know a session
    /// happened, not what was in it.
    func loadOverview(for session: PostableSession) async {
        guard let repository,
              sessionOverviews[session.sessionID] == nil,
              !loadingOverviewIDs.contains(session.sessionID) else {
            return
        }
        let generation = connectionGeneration
        loadingOverviewIDs.insert(session.sessionID)
        defer {
            if connectionGeneration == generation {
                loadingOverviewIDs.remove(session.sessionID)
            }
        }

        let loaded = try? await repository.sessionOverview(
            sessionID: session.sessionID,
            performedAt: session.performedAt
        )
        guard connectionGeneration == generation, let loaded else { return }
        sessionOverviews[session.sessionID] = loaded
    }

    /// Clears a day and starts it again in one step.
    ///
    /// The day has to be cleared first. A second session left beside the first
    /// would be a second record of the same day, which is the thing that
    /// inflated the count before.
    func redoSession(workoutName: String, on date: Date, day: Weekday, workoutID: Workout.ID?) async {
        await undoCompletion(workoutName: workoutName, on: date)
        guard persistenceError == nil else { return }
        startSession(on: day, workoutID: workoutID)
    }

    /// Undoes a day's training by deleting every finished session recorded for
    /// it, which is what removes it from the counts.
    ///
    /// Every session for the day goes, not the newest one: a day that was
    /// started twice would otherwise still read as trained after an undo, and
    /// the user asked for one undo per day rather than one per attempt.
    func undoCompletion(workoutName: String, on date: Date) async {
        guard let repository else { return }
        let doomed = finishedSessions(workoutName: workoutName, on: date)
        guard !doomed.isEmpty else { return }

        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil
        defer { if connectionGeneration == generation { isSaving = false } }

        do {
            for session in doomed {
                try await repository.discardSession(id: session.sessionID)
            }
            guard connectionGeneration == generation else { return }
            // Drop them locally too, so the count falls now rather than after
            // the reload comes back.
            let removed = Set(doomed.map(\.sessionID))
            dashboardSessions.removeAll { removed.contains($0.sessionID) }
            postableSessions.removeAll { removed.contains($0.sessionID) }
            completedSessions.removeAll { removed.contains($0.session.serverID) }
            for id in removed { sessionOverviews[id] = nil }
            await loadDashboardSessions()
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.localizedDescription
        }
    }

    // MARK: - Last time

    /// The set the hint should show: the same set number from the last time
    /// this exercise was trained in this workout.
    ///
    /// Falls back to that exercise's last set when the previous session was
    /// shorter than this one, so a fourth set added today still has something
    /// to aim at rather than nothing.
    func previousSet(exerciseServerID: Int?, setNumber: Int) -> PreviousSet? {
        guard let exerciseServerID, let sets = previousSets[exerciseServerID] else {
            return nil
        }
        return sets.first { $0.setNumber == setNumber } ?? sets.last
    }

    /// Reads what was lifted last time, for the session that just started.
    ///
    /// A failure is swallowed rather than surfaced. This is a hint beside a
    /// field the user is about to type in; a red banner over a working session
    /// because last week could not be read would cost more than the hint is
    /// worth.
    private func loadPreviousSets(
        for session: ActiveWorkoutSession,
        using repository: WorkoutAPIRepository,
        generation: UUID
    ) async {
        let loaded = try? await repository.previousSets(
            excludingSessionID: session.serverID
        )
        guard connectionGeneration == generation else { return }
        previousSets = loaded ?? [:]
    }

    // MARK: - Posting

    /// Reads the finished sessions the composer offers.
    ///
    /// Read again each time the composer opens rather than cached: a session
    /// finished since it was last opened is exactly the one most likely to be
    /// posted. A failure is reported through `persistenceError` like every
    /// other read, so the composer can say so instead of showing an empty list
    /// that looks like "you have never trained".
    func loadPostableSessions() async {
        guard let repository else { return }
        let generation = connectionGeneration
        isLoadingPostableSessions = true
        defer {
            if connectionGeneration == generation {
                isLoadingPostableSessions = false
            }
        }

        do {
            let sessions = try await repository.completedSessions()
            guard connectionGeneration == generation else { return }
            postableSessions = sessions
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.localizedDescription
        }
    }

    /// Loads the complete finished-session history for dashboard statistics.
    /// The existing API does not expose aggregate totals or streaks, so those
    /// small calculations are performed locally from server-owned timestamps.
    func loadDashboardSessions() async {
        guard let repository, !isLoadingDashboardSessions else { return }
        let generation = connectionGeneration
        isLoadingDashboardSessions = true
        defer {
            if connectionGeneration == generation {
                isLoadingDashboardSessions = false
            }
        }

        do {
            // The totals come from the server now, so this no longer has to
            // page the whole history to produce them. What is still read is a
            // bounded window, for the completed badges on the week strip and
            // on a day that is opened.
            async let statsRequest = repository.trainingStats()
            async let sessionsRequest = repository.completedSessions(
                since: Calendar.current.date(
                    byAdding: .day,
                    value: -Self.badgeHistoryDays,
                    to: Date()
                )
            )
            let (stats, sessions) = try await (statsRequest, sessionsRequest)
            guard connectionGeneration == generation else { return }
            trainingStats = stats
            dashboardSessions = sessions
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.localizedDescription
        }
    }

    /// How far back the badge lookup reads.
    ///
    /// Only the current week is ever marked on the strip, and a day page asks
    /// about the day it is showing, so this is generous rather than exact. It
    /// exists so the read is bounded at all: it used to be every session the
    /// account had, fetched again on every visit.
    static let badgeHistoryDays = 120

    // MARK: - Lookups

    /// Everything planned for a day, in schedule order.
    func workouts(on day: Weekday) -> [Workout] {
        schedule[day] ?? []
    }

    /// Every concrete workout scheduled in the current week, in weekday and
    /// schedule order. Planner synchronization reads this projection rather
    /// than reaching into the store's private dictionary.
    var currentWeekWorkouts: [Workout] {
        Weekday.allCases.flatMap { workouts(on: $0) }
    }

    /// The day's primary workout — the first one scheduled. Days with a single
    /// workout behave exactly as before.
    func workout(on day: Weekday) -> Workout? {
        schedule[day]?.first
    }

    /// How many workouts are planned for a day, so the UI can show when there
    /// is more than one rather than silently hiding the rest.
    func workoutCount(on day: Weekday) -> Int {
        schedule[day]?.count ?? 0
    }

    func workout(id: Workout.ID, on day: Weekday) -> Workout? {
        schedule[day]?.first { $0.id == id }
    }

    func activeSession(on day: Weekday) -> ActiveWorkoutSession? {
        guard activeSession?.day == day else { return nil }
        return activeSession
    }

    var today: Weekday? {
        Weekday(
            calendarWeekday: Calendar.current.component(
                .weekday,
                from: Date()
            )
        )
    }

    var isEditingEnabled: Bool {
        repository != nil && !isLoading && !isSaving
    }

    /// True when there is no API connection at all, as opposed to a transient
    /// load or save. Only this state is worth offering a retry for.
    var repositoryIsMissing: Bool { repository == nil }

    /// Why editing is unavailable, so a disabled control can say so instead of
    /// looking broken. Nil when editing is available.
    var editingBlockedReason: String? {
        if repository == nil {
            return "Not connected to Repbase. Check your connection and retry."
        }
        if isLoading { return "Loading this week…" }
        if isSaving { return "Saving…" }
        return nil
    }

    var hasPendingSetChanges: Bool {
        !pendingSetIDs.isEmpty
    }

    /// Reads the GPS track of a finished session so its summary can draw it.
    ///
    /// A missing track is not an error worth reporting: a run recorded indoors,
    /// or with location refused, simply has none, and the summary leaves the
    /// map out rather than saying so.
    func loadCompletedRoute(sessionID: Int) async {
        guard let repository else { return }
        let generation = connectionGeneration
        let points = (try? await repository.route(sessionID: sessionID)) ?? []
        guard connectionGeneration == generation else { return }
        completedRoute = points
    }

    func isSetPending(_ id: WorkoutSetDraft.ID) -> Bool {
        pendingSetIDs.contains(id)
    }

    func dateLabel(for day: Weekday) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = .current
        formatter.dateFormat = "MMM d"
        return formatter.string(from: workoutDate(for: day))
    }

    // MARK: - Day management

    /// Schedules a workout the user already has on a date.
    ///
    /// Separate from `saveWorkout`, which sends a draft and lets the server
    /// match it to a template by name. There is no draft here: the template is
    /// known by id, so only a schedule row is written and the saved workout —
    /// its exercises, their relationship rows, their target sets — is left
    /// exactly as it was, wherever else it is also planned.
    ///
    /// Returns whether it was scheduled, so the caller can report the failure
    /// rather than closing as though it had worked.
    @discardableResult
    func scheduleKnownWorkout(_ summary: WorkoutSummary, on date: Date) async -> Bool {
        guard let repository, !isSaving else { return false }
        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil
        defer { if connectionGeneration == generation { isSaving = false } }

        do {
            try await repository.scheduleExistingWorkout(
                templateID: summary.serverID,
                on: Self.dateString(date)
            )
            guard connectionGeneration == generation else { return false }
            await reloadWeek(
                using: repository,
                generation: generation,
                showsLoadingState: false
            )
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            persistenceError = error.localizedDescription
            return false
        }
    }

    /// `YYYY-MM-DD` in the device's own calendar, matching every other date
    /// this app sends.
    nonisolated static func dateString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    /// Saves a workout without putting it on any date, and answers with its
    /// server id. Nil means it did not save, and the caller should not pretend
    /// otherwise — `persistenceError` says why.
    ///
    /// For rotations: the cycle writes its own dates from its anchor, so the
    /// workout has to exist as a template first and be scheduled by nothing
    /// else. A name already in use resolves to that workout rather than a
    /// second copy of it.
    func createTemplate(_ workout: Workout) async -> Int? {
        guard let repository, !isSaving else { return nil }
        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil
        defer { isSaving = false }

        do {
            let id = try await repository.createTemplate(Self.normalized(workout))
            guard connectionGeneration == generation else { return nil }
            // So the new workout is offered the next time a day is set, and
            // so the slot can name it without waiting for the next load.
            await reloadWeek(
                using: repository,
                generation: generation,
                showsLoadingState: false
            )
            return id
        } catch {
            guard connectionGeneration == generation else { return nil }
            persistenceError = error.localizedDescription
            return nil
        }
    }

    func saveWorkout(_ workout: Workout, on day: Weekday) {
        guard let repository, !isSaving else { return }
        let generation = connectionGeneration
        // Only an edit of a workout already on this day replaces it; anything
        // else is scheduled alongside whatever is already planned.
        let existing = schedule[day]?.first { $0.id == workout.id }
        let date = dateString(for: day)
        let workout = Self.normalized(workout)
        isSaving = true
        persistenceError = nil

        Task {
            do {
                try await repository.saveWorkout(
                    workout,
                    replacing: existing,
                    scheduledDate: date
                )
                await reloadWeek(
                    using: repository,
                    generation: generation,
                    showsLoadingState: false
                )
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.localizedDescription
            }
            // Cleared unconditionally. Operations are serialized by the
            // `!isSaving` guard at entry, so no newer save can be running, and
            // a stale return must not leave the day editor permanently
            // disabled with nothing on screen explaining it.
            isSaving = false
        }
    }

    /// Removes one workout from a day. Other workouts planned for that day are
    /// untouched, and the workout template itself is kept.
    func removeWorkout(_ workout: Workout, on day: Weekday) {
        guard let repository, !isSaving else { return }
        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil

        Task {
            do {
                try await repository.removeSchedule(workout)
                guard connectionGeneration == generation else { return }
                schedule[day]?.removeAll { $0.id == workout.id }
                if schedule[day]?.isEmpty == true {
                    schedule.removeValue(forKey: day)
                }
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.localizedDescription
            }
            // Cleared unconditionally. Operations are serialized by the
            // `!isSaving` guard at entry, so no newer save can be running, and
            // a stale return must not leave the day editor permanently
            // disabled with nothing on screen explaining it.
            isSaving = false
        }
    }

    /// Turns a workout's weekly repeat on or off.
    ///
    /// Turning it off leaves this week, and every week already finished, exactly
    /// as they are: those days are on the calendar and some of them have been
    /// trained. Only the weeks the repeat had planned ahead are cleared.
    func setRepeat(_ workout: Workout, on day: Weekday, repeats: Bool) {
        guard let repository, !isSaving else { return }
        guard workout.repeatsWeekly != repeats else { return }
        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil

        Task {
            do {
                let recurrenceID: Int?
                if repeats {
                    recurrenceID = try await repository.startRepeating(
                        workout,
                        on: day
                    )
                } else {
                    try await repository.stopRepeating(workout)
                    recurrenceID = nil
                }
                guard connectionGeneration == generation else { return }
                mutateWorkout(workout, on: day) { $0.recurrenceID = recurrenceID }
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.localizedDescription
            }
            // Cleared unconditionally, for the same reason as the saves above.
            isSaving = false
        }
    }

    private func mutateWorkout(
        _ workout: Workout,
        on day: Weekday,
        _ mutation: (inout Workout) -> Void
    ) {
        guard let index = schedule[day]?.firstIndex(where: { $0.id == workout.id })
        else { return }
        mutation(&schedule[day]![index])
    }

    // MARK: - Session logging

    /// Starts a session for one of the day's workouts, defaulting to the first.
    func startSession(on day: Weekday, workoutID: Workout.ID? = nil) {
        let candidate = workoutID.flatMap { workout(id: $0, on: day) }
            ?? workout(on: day)
        guard let repository,
              activeSession == nil,
              let workout = candidate,
              // A run, ride, or swim is logged as a distance, so it needs no
              // planned exercises before it can start.
              workout.tracksDistance || !workout.exercises.isEmpty,
              !isSaving else {
            return
        }
        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil

        Task {
            do {
                let session = try await repository.startSession(
                    for: workout,
                    on: day
                )
                guard connectionGeneration == generation else { return }
                activeSession = session
                routeSummary = nil
                completedRoute = []
                previousSets = [:]
                // Only a run, ride, or swim records a track, and only for as
                // long as its session is active.
                if session.tracksDistance {
                    routeTracker.startTracking()
                }
                // Read after the session is on screen rather than before, so
                // the first set can be typed while last week is still loading.
                if !session.tracksDistance {
                    await loadPreviousSets(
                        for: session,
                        using: repository,
                        generation: generation
                    )
                }
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.localizedDescription
            }
            // Cleared unconditionally. Operations are serialized by the
            // `!isSaving` guard at entry, so no newer save can be running, and
            // a stale return must not leave the day editor permanently
            // disabled with nothing on screen explaining it.
            isSaving = false
        }
    }

    func updateSessionSet(
        on day: Weekday,
        exerciseID: Exercise.ID,
        setID: WorkoutSetDraft.ID,
        weightKilograms: String? = nil,
        reps: String? = nil,
        distanceKilometers: String? = nil
    ) {
        mutateSet(on: day, exerciseID: exerciseID, setID: setID) { set in
            if let weightKilograms {
                set.weightKilograms = weightKilograms
            }
            if let reps {
                set.reps = reps
            }
            if let distanceKilometers {
                set.distanceKilometers = distanceKilometers
            }
        }
    }

    func toggleSessionSetLogged(
        on day: Weekday,
        exerciseID: Exercise.ID,
        setID: WorkoutSetDraft.ID
    ) {
        guard let repository,
              !pendingSetIDs.contains(setID),
              let session = activeSession(on: day),
              let exercise = sessionExercise(on: day, id: exerciseID),
              let set = exercise.sets.first(where: { $0.id == setID }) else {
            return
        }
        let workoutType = session.workoutType

        pendingSetIDs.insert(setID)
        persistenceError = nil
        Task {
            do {
                if set.isLogged {
                    guard let entryID = set.serverID else {
                        throw APIServiceError.missingServerIdentifier("Set entry")
                    }
                    try await repository.deleteSetEntry(id: entryID)
                    mutateSet(on: day, exerciseID: exerciseID, setID: setID) {
                        $0.serverID = nil
                        $0.isLogged = false
                    }
                } else {
                    let entryID = try await repository.logSet(
                        set,
                        sessionExerciseID: exercise.sessionExerciseID,
                        workoutType: workoutType
                    )
                    mutateSet(on: day, exerciseID: exerciseID, setID: setID) {
                        $0.serverID = entryID
                        $0.isLogged = true
                    }
                }
            } catch {
                persistenceError = error.localizedDescription
            }
            pendingSetIDs.remove(setID)
        }
    }

    func addSessionSet(on day: Weekday, exerciseID: Exercise.ID) {
        mutateSession(on: day) { session in
            guard let index = session.exercises.firstIndex(
                where: { $0.id == exerciseID }
            ) else {
                return
            }
            let nextNumber = session.exercises[index].sets.count + 1
            session.exercises[index].sets.append(
                WorkoutSetDraft(setNumber: nextNumber)
            )
        }
    }

    func removeLastSessionSet(on day: Weekday, exerciseID: Exercise.ID) {
        guard let repository,
              let exercise = sessionExercise(on: day, id: exerciseID),
              exercise.sets.count > 1,
              let lastSet = exercise.sets.last,
              !pendingSetIDs.contains(lastSet.id) else {
            return
        }

        guard let entryID = lastSet.serverID else {
            removeSessionSet(
                on: day,
                exerciseID: exerciseID,
                setID: lastSet.id
            )
            return
        }

        pendingSetIDs.insert(lastSet.id)
        Task {
            do {
                try await repository.deleteSetEntry(id: entryID)
                removeSessionSet(
                    on: day,
                    exerciseID: exerciseID,
                    setID: lastSet.id
                )
            } catch {
                persistenceError = error.localizedDescription
            }
            pendingSetIDs.remove(lastSet.id)
        }
    }

    func endSession(on day: Weekday) async -> Int? {
        guard let repository,
              let session = activeSession,
              session.day == day,
              pendingSetIDs.isEmpty,
              !isSaving else {
            return nil
        }

        isSaving = true
        persistenceError = nil
        defer { isSaving = false }
        do {
            // Upload the track before ending so the session's distance and
            // pace are already computed when the completion summary appears.
            let recorded = routeTracker.stopTracking()
            if session.tracksDistance, recorded.count >= 2 {
                do {
                    routeSummary = try await repository.uploadRoute(
                        recorded,
                        sessionID: session.serverID
                    )
                } catch {
                    // The workout itself still counts; say the track failed
                    // rather than losing the session over it.
                    persistenceError = "Session saved, but the route could not be uploaded: \(error.localizedDescription)"
                }
            }

            try await repository.endSession(id: session.serverID)
            completedSessions.append(
                CompletedWorkoutSession(session: session, endedAt: Date())
            )
            activeSession = nil
            routeTracker.reset()

            // Keep the dashboard current when the user returns from the
            // finished session. The totals are the server's, so this asks for
            // them again rather than re-deriving them from a full history
            // download, and the badge window stays bounded.
            if let stats = try? await repository.trainingStats() {
                trainingStats = stats
            }
            if let refreshed = try? await repository.completedSessions(
                since: Calendar.current.date(
                    byAdding: .day,
                    value: -Self.badgeHistoryDays,
                    to: Date()
                )
            ) {
                dashboardSessions = refreshed
            }

            // Load what the summary needs. A failure here costs only the
            // chart or the record list, so the finished workout is still
            // reported as saved either way.
            if session.tracksDistance {
                sessionHistory = (try? await repository.sessionHistory(
                    workoutName: session.workoutName
                )) ?? []
            } else {
                personalRecords = (try? await repository.personalRecords(
                    sessionID: session.serverID
                )) ?? []

                var progress: [LiftProgressSeries] = []
                for exercise in session.exercises {
                    if let series = try? await repository.liftProgress(
                        exerciseID: exercise.exerciseServerID,
                        exerciseName: exercise.name,
                        workoutName: session.workoutName
                    ), series.hasEnoughToPlot {
                        progress.append(series)
                    }
                }
                liftProgress = progress
            }

            return session.loggedSetCount
        } catch {
            persistenceError = error.localizedDescription
            return nil
        }
    }

    func discardSession(on day: Weekday) async {
        guard let repository,
              let session = activeSession,
              session.day == day,
              pendingSetIDs.isEmpty,
              !isSaving else {
            return
        }

        isSaving = true
        persistenceError = nil
        defer { isSaving = false }
        do {
            try await repository.discardSession(id: session.serverID)
            activeSession = nil
            // A discarded session keeps no track.
            routeTracker.reset()
            routeSummary = nil
            completedRoute = []
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    // MARK: - Retry and mapping

    /// Reconnects and reloads. Callable whenever a repository exists, so a
    /// failed load can always be retried.
    func retryPersistence() {
        guard let repository, !isSaving else { return }
        let generation = connectionGeneration
        Task {
            await reloadWeek(
                using: repository,
                generation: generation,
                showsLoadingState: true
            )
        }
    }

    private func reloadWeek(
        using repository: WorkoutAPIRepository,
        generation: UUID,
        showsLoadingState: Bool
    ) async {
        if showsLoadingState { isLoading = true }
        // The flag is cleared no matter how this exits. Leaving it set after a
        // stale return would disable every editing control with nothing on
        // screen to explain why, and retryPersistence() would refuse to run.
        defer { if showsLoadingState { isLoading = false } }

        persistenceError = nil
        do {
            let loaded = try await repository.loadWeek(
                dateByDay: dateStringsForCurrentWeek()
            )
            guard connectionGeneration == generation else { return }
            schedule = loaded.schedule
            // Names to offer when creating a workout, built from the templates
            // the schedule was built from. This was a second sequential request
            // for rows the first one had already read.
            knownWorkouts = loaded.library
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.localizedDescription
        }
    }

    private func sessionExercise(
        on day: Weekday,
        id: Exercise.ID
    ) -> SessionExerciseDraft? {
        activeSession(on: day)?.exercises.first(where: { $0.id == id })
    }

    private func mutateSet(
        on day: Weekday,
        exerciseID: Exercise.ID,
        setID: WorkoutSetDraft.ID,
        _ mutation: (inout WorkoutSetDraft) -> Void
    ) {
        mutateSession(on: day) { session in
            guard let exerciseIndex = session.exercises.firstIndex(
                where: { $0.id == exerciseID }
            ),
                  let setIndex = session.exercises[exerciseIndex].sets
                    .firstIndex(where: { $0.id == setID }) else {
                return
            }
            mutation(&session.exercises[exerciseIndex].sets[setIndex])
        }
    }

    private func removeSessionSet(
        on day: Weekday,
        exerciseID: Exercise.ID,
        setID: WorkoutSetDraft.ID
    ) {
        mutateSession(on: day) { session in
            guard let index = session.exercises.firstIndex(
                where: { $0.id == exerciseID }
            ) else {
                return
            }
            session.exercises[index].sets.removeAll { $0.id == setID }
        }
    }

    private func mutateSession(
        on day: Weekday,
        _ mutation: (inout ActiveWorkoutSession) -> Void
    ) {
        guard var session = activeSession, session.day == day else { return }
        mutation(&session)
        activeSession = session
    }

    private func dateStringsForCurrentWeek(
        referenceDate: Date = Date()
    ) -> [Weekday: String] {
        Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map {
                ($0, dateString(for: $0, referenceDate: referenceDate))
            }
        )
    }

    private func dateString(
        for day: Weekday,
        referenceDate: Date = Date()
    ) -> String {
        let calendar = Calendar.current
        let date = workoutDate(for: day, referenceDate: referenceDate)
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    /// The weekday a `YYYY-MM-DD` date falls on, but only within the week the
    /// schedule holds.
    ///
    /// Nil for any other date. The schedule is one week wide, so a day view
    /// for last Tuesday opens on an empty page — better to know that before
    /// offering to go there.
    func weekday(forDateString value: String) -> Weekday? {
        Weekday.allCases.first { dateString(for: $0) == value }
    }

    /// The calendar date this weekday falls on in the week being shown.
    /// Exposed so a day can ask whether it has already been trained.
    func workoutDate(
        for day: Weekday,
        referenceDate: Date = Date()
    ) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: referenceDate)
        let calendarWeekday = calendar.component(.weekday, from: start)
        let daysSinceMonday = (calendarWeekday + 5) % 7
        let monday = calendar.date(
            byAdding: .day,
            value: -daysSinceMonday,
            to: start
        ) ?? start
        return calendar.date(
            byAdding: .day,
            value: day.rawValue - 1,
            to: monday
        ) ?? monday
    }

    /// Begins timing a cardio finisher for a session that has already ended.
    func startCardio(machine: CardioMachine, sessionID: Int) {
        guard cardioStartedAt == nil else { return }
        cardioMachine = machine
        cardioSessionID = sessionID
        cardioStartedAt = Date()
        recordedCardioSeconds = nil
    }

    /// Stops timing and records the finisher against its session.
    @discardableResult
    func finishCardio(distanceKilometers: Double? = nil) async -> Bool {
        guard let repository,
              let startedAt = cardioStartedAt,
              let machine = cardioMachine,
              let sessionID = cardioSessionID else {
            return false
        }

        let seconds = max(1, Int(Date().timeIntervalSince(startedAt).rounded()))
        cardioStartedAt = nil
        persistenceError = nil

        do {
            try await repository.recordCardio(
                sessionID: sessionID,
                machine: machine,
                seconds: seconds,
                distanceKilometers: distanceKilometers
            )
            recordedCardioSeconds = seconds
            cardioSessionID = nil
            return true
        } catch {
            // The time is kept on screen so it is not lost to a failed save.
            cardioStartedAt = startedAt
            persistenceError = "Cardio could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    func cancelCardio() {
        cardioStartedAt = nil
        cardioMachine = nil
        cardioSessionID = nil
    }

    /// A distance workout is logged as a single effort, but the API records
    /// every effort against a session exercise. Give one to a run, ride, or
    /// swim that has none so the user never has to invent an exercise for it.
    private static func normalized(_ workout: Workout) -> Workout {
        guard workout.type.tracksDistance, workout.exercises.isEmpty else {
            return workout
        }
        var workout = workout
        workout.exercises = [
            Exercise(name: workout.type.title, sets: 1)
        ]
        return workout
    }
}

// MARK: - Preview fixtures

extension WorkoutStore {
    static let previewWorkouts: [Workout] = [
        Workout(name: "Upper Body", exercises: [
            Exercise(name: "Bench Press", sets: 4),
            Exercise(name: "Overhead Press", sets: 3),
            Exercise(name: "Pull-Ups", sets: 3)
        ]),
        Workout(name: "Lower Body", exercises: [
            Exercise(name: "Back Squat", sets: 4),
            Exercise(name: "Romanian Deadlift", sets: 3),
            Exercise(name: "Calf Raise", sets: 3)
        ]),
        Workout(name: "Full Body Conditioning", exercises: [
            Exercise(name: "Kettlebell Swing", sets: 4),
            Exercise(name: "Burpees", sets: 3)
        ]),
        Workout(name: "Core & Mobility", exercises: [
            Exercise(name: "Plank", sets: 3),
            Exercise(name: "Hanging Leg Raise", sets: 3)
        ])
    ]

    static var preview: WorkoutStore {
        let workouts = previewWorkouts
        return WorkoutStore(
            initialSchedule: [
                .monday: [workouts[0]],
                .tuesday: [workouts[1]],
                // Thursday carries two, so previews exercise the
                // multiple-workouts-in-a-day layout.
                .thursday: [workouts[2], workouts[3]],
                .friday: [workouts[3]]
            ]
        )
    }

    /// The same, with a saved library behind it. The rotation editor picks
    /// each day out of `knownWorkouts`, so without this its only screen is
    /// the one telling you to go and save a workout first.
    static var previewWithLibrary: WorkoutStore {
        let store = preview
        store.knownWorkouts = previewWorkouts.enumerated().map { index, workout in
            WorkoutSummary(
                serverID: index + 1,
                name: workout.name,
                type: .lifting,
                exercises: workout.exercises
            )
        }
        return store
    }
}
