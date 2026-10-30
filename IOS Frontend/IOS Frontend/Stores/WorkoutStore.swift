//
//  WorkoutStore.swift
//  IOS Frontend
//
//  Main-actor state backed by the generated Repbase API client.
//

import Foundation
import Observation

/// The small amount of before/after state the Training dashboard needs to
/// replay a finished workout as a visible accomplishment when the user comes
/// back to it. The server still owns every number; this only preserves the
/// previous values long enough to animate to the refreshed response.
struct TrainingDashboardReward {
    let workoutName: String
    let day: Weekday
    let previousCompletedThisWeek: Int
    let completedThisWeek: Int
    let previousTotalWorkouts: Int
    let totalWorkouts: Int
}

@Observable
final class WorkoutStore {
    private var repository: WorkoutAPIRepository?
    private let recovery = PendingWorkoutSaves()
    private var recoveryOwnerID: Int?
    private var recoveryOrigin = ""
    private(set) var pendingWorkoutSaveCount = 0
    private(set) var recoveryError: String?
    private(set) var isRecoveringWorkouts = false

    /// Whether this store can reach the server yet.
    ///
    /// Read by the screens whose first load runs before the session has been
    /// restored. Their .task fires on appear, finds no repository, and
    /// returns -- and without something to key on, never runs again.
    var isConnected: Bool { repository != nil }

    func preferredWeightUnit() async throws -> WorkoutWeightUnit {
        guard let repository else { return .metric }
        let generation = connectionGeneration
        let unit = try await repository.preferredWeightUnit()
        guard generation == connectionGeneration else { throw CancellationError() }
        return unit
    }

    func exerciseChoices(page: Int = 1, search: String? = nil, mine: Bool = false) async throws -> WorkoutExercisePage {
        guard let repository else {
            throw APIServiceError.missingServerIdentifier(
                String(localized: "Account connection", bundle: .app, locale: .app, comment: "Names what is missing in “%@ has not been saved to the server yet.”")
            )
        }
        let generation = connectionGeneration
        let result = try await repository.exerciseChoices(page: page, search: search, mine: mine)
        guard generation == connectionGeneration else { throw CancellationError() }
        return result
    }

    /// Writes the account's default weight unit and answers with what the
    /// server stored.
    func savePreferredWeightUnit(_ unit: WorkoutWeightUnit) async throws -> WorkoutWeightUnit {
        guard let repository else { throw APIServiceError.undocumentedStatus(0) }
        let generation = connectionGeneration
        let saved = try await repository.setPreferredWeightUnit(unit)
        guard generation == connectionGeneration else { throw CancellationError() }
        return saved
    }
    private var connectionGeneration = UUID()
    private let scheduleReads = CalendarReadGate()
    /// Invalidates dependent planner data even if this week's rows are unchanged.
    private(set) var calendarRevision: UInt64 = 0

    /// Current-week projection of concrete API WorkoutSchedule records. A date
    /// can hold more than one schedule, so each day maps to a list.
    private(set) var schedule: [Weekday: [Workout]]
    /// Set only after a save's returned template is found in the authoritative
    /// schedule. The day view can reveal exactly the newly saved card.
    private(set) var lastSavedWorkoutID: Workout.ID?
    private(set) var persistenceError: String?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var activeSession: ActiveWorkoutSession? {
        didSet {
            checkpointActiveSession()
            publishSessionSignals()
        }
    }
    /// Weight unit and rest settings, read by every workout screen.
    let preferences = WorkoutPreferences()
    /// The exercises people choose from, shared by the workout builder and
    /// the add-exercise sheet of a session in progress, so an exercise
    /// created in one is offered in the other straight away.
    let catalog = ExerciseCatalog()
    /// Keeps the Lock Screen and Dynamic Island in step with the session.
    private let liveActivity = WorkoutLiveActivityController()
    /// Says when a rest is over while the app is not on screen.
    private let restNotifier = RestTimerNotifier()
    /// Set while a connection is restoring the session; see
    /// `publishSessionSignals`.
    private var holdsSessionSignals = false
    private(set) var recoveredActiveSession = false
    private var lastCheckpointAt = Date.distantPast
    private struct ActiveCheckpoint: Codable {
        let session: ActiveWorkoutSession
        let points: [RoutePoint]
    }
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

    /// The names of these workouts that already come back every week.
    ///
    /// A rotation and a weekly repeat both write the same dates, so the server
    /// refuses a rotation containing one. Asking here rather than finding out
    /// from the refusal is what lets the editor offer to stop them instead of
    /// reporting an error somebody then has to go and act on themselves.
    func weeklyRepeatNames(among workoutIDs: Set<Int>) -> [String] {
        var found: [Int: String] = [:]
        for workouts in schedule.values {
            for workout in workouts where workout.repeatsWeekly {
                guard let serverID = workout.serverID,
                      workoutIDs.contains(serverID) else { continue }
                found[serverID] = workout.name
            }
        }
        return found.values.sorted()
    }
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
    private(set) var pendingTrainingDashboardReward: TrainingDashboardReward?

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
        // Read the exercise library off the main thread now, so the first
        // search in the builder does not pay for parsing it.
        Task.detached(priority: .utility) { _ = ExerciseLibrary.shared }
        routeTracker.onPointsChanged = { [weak self] in self?.checkpointActiveSession(force: false) }
        catalog.source = { [weak self] page, search, mine in
            guard let self else { throw CancellationError() }
            return try await self.exerciseChoices(page: page, search: search, mine: mine)
        }
        // Lock Screen buttons run their intent in this process. Installed
        // here, at launch, so a tap that wakes the app finds somewhere to go.
        WorkoutActivityActionCenter.shared.install { [weak self] action in
            await self?.handleLiveActivityAction(action)
        }
    }

    /// Tells the Lock Screen and the rest notification what the session looks
    /// like now. Called on every change to it; both skip work when nothing
    /// they show has changed.
    private func publishSessionSignals() {
        // A connection clears the session and then restores it from the
        // checkpoint. In between it is nil only because it has not been read
        // yet, and taking that for "the workout ended" would remove the Lock
        // Screen activity -- which, with the app woken in the background by a
        // tap on it, could not be started again until it was opened.
        guard !holdsSessionSignals else { return }
        let session = activeSession.flatMap { $0.tracksDistance ? nil : $0 }
        liveActivity.sync(
            session: session,
            enabled: preferences.liveActivity,
            unit: preferences.weightUnit,
            previous: { [weak self] exercise, index in self?.previousSet(for: exercise, at: index) }
        )
        restNotifier.sync(
            session: session,
            enabled: preferences.restAlerts
        )
    }

    /// For a settings switch that changes what the signals should show.
    func refreshSessionSignals() { publishSessionSignals() }

    // MARK: - Connection

    func connect(configuration: APIConfiguration, token: String, accountID: Int? = nil) async {
        recoveryOwnerID = accountID
        recoveryOrigin = configuration.serverURL.absoluteString
        let generation = UUID()
        connectionGeneration = generation
        scheduleReads.invalidate()
        lastSavedWorkoutID = nil
        holdsSessionSignals = true
        activeSession = nil
        pendingSetIDs = []
        // A fresh connection owns these flags; never inherit a stuck one.
        isLoading = false
        isSaving = false
        defer {
            if connectionGeneration == generation {
                holdsSessionSignals = false
                publishSessionSignals()
            }
        }

        do {
            let repository = try WorkoutAPIRepository(
                configuration: configuration,
                token: token,
                recoveryScope: EditorDraftRecovery.shared.scope
            )
            self.repository = repository
            catalog.reset()
            await reloadWeek(
                using: repository,
                generation: generation,
                showsLoadingState: true
            )
            await restoreActiveCheckpoint(using: repository, generation: generation)
            // Read once per connection rather than by every screen that shows
            // a weight. A failure keeps kilograms, which is what the stored
            // numbers are; it is never a reason to stop a workout.
            if let unit = try? await repository.preferredWeightUnit(), generation == connectionGeneration {
                preferences.adoptAccountUnit(unit)
            }
        } catch {
            self.repository = nil
            schedule = [:]
            persistenceError = error.userFacingMessage
        }
    }

    func disconnect() {
        checkpointActiveSession()
        recoveredActiveSession = false
        recoveryOwnerID = nil
        pendingWorkoutSaveCount = 0
        recoveryError = nil
        isRecoveringWorkouts = false
        connectionGeneration = UUID()
        scheduleReads.invalidate()
        routeTracker.reset()
        trainingStats = .empty
        completedSessions = []
        repository = nil
        schedule = [:]
        lastSavedWorkoutID = nil
        // Signing out does end the session on this phone, Lock Screen and all.
        holdsSessionSignals = false
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
        pendingTrainingDashboardReward = nil
        cardioStartedAt = nil
        cardioMachine = nil
        cardioSessionID = nil
        recordedCardioSeconds = nil
        sessionHistory = []
        personalRecords = []
        liftProgress = []
        routeSummary = nil
        completedRoute = []
        preferences.reset()
        catalog.reset()
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

    /// Saved-template identity is authoritative even if another workout has
    /// the same name, or this template was renamed after a session finished.
    func finishedSessions(workout: Workout, on date: Date) -> [PostableSession] {
        let day = Calendar.current.startOfDay(for: date)
        return dashboardSessions.filter {
            $0.recordedSomething
                && WorkoutSelectionPolicy.sameTemplate(expected: workout.serverID, actual: $0.workoutServerID)
                && Calendar.current.startOfDay(for: $0.performedAt) == day
        }
    }

    func isCompleted(workout: Workout, on date: Date) -> Bool {
        !finishedSessions(workout: workout, on: date).isEmpty
    }

    func isCompleted(workoutServerID: Int, on date: Date) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        return dashboardSessions.contains {
            $0.recordedSomething
                && WorkoutSelectionPolicy.sameTemplate(expected: workoutServerID, actual: $0.workoutServerID)
                && Calendar.current.startOfDay(for: $0.performedAt) == day
        }
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
    func redoSession(workout: Workout, on date: Date, day: Weekday) async {
        await undoCompletion(workout: workout, on: date)
        guard persistenceError == nil else { return }
        startSession(on: day, workoutID: workout.id)
    }

    /// Undoes a day's training by deleting every finished session recorded for
    /// it, which is what removes it from the counts.
    ///
    /// Every session for the day goes, not the newest one: a day that was
    /// started twice would otherwise still read as trained after an undo, and
    /// the user asked for one undo per day rather than one per attempt.
    func undoCompletion(workout: Workout, on date: Date) async {
        await undoCompletion(sessions: finishedSessions(workout: workout, on: date))
    }

    private func undoCompletion(sessions doomed: [PostableSession]) async {
        guard let repository, !isSaving else { return }
        guard !doomed.isEmpty else { return }

        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil
        defer { if connectionGeneration == generation { isSaving = false } }

        do {
            for session in doomed {
                try await repository.discardSession(id: session.sessionID)
                guard connectionGeneration == generation else { return }
                // Each confirmed deletion may reopen the server's planner task.
                // Notify even if a later deletion in this batch fails.
                calendarRevision &+= 1
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
            persistenceError = error.userFacingMessage
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

    /// The hint for the set in this row, matched by kind and place: today's
    /// first working set against last time's first working set, warm-ups
    /// against warm-ups. See `WorkoutSetPolicy.previousIndex`.
    func previousSet(for exercise: SessionExerciseDraft, at index: Int) -> PreviousSet? {
        guard let sets = previousSets[exercise.exerciseServerID], !sets.isEmpty else { return nil }
        let match = WorkoutSetPolicy.previousIndex(
            at: index,
            types: exercise.sets.map(\.setType),
            previousTypes: sets.map { $0.setType ?? .normal }
        )
        return match.map { sets[$0] }
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
            persistenceError = error.userFacingMessage
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
            persistenceError = error.userFacingMessage
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
    /// schedule order. Dates, not weekday names, identify concrete schedules.
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
            return String(localized: "Not connected to Rytivo. Check your connection and retry.", bundle: .app, locale: .app)
        }
        if isLoading { return String(localized: "Loading this week…", bundle: .app, locale: .app) }
        if isSaving { return String(localized: "Saving…", bundle: .app, locale: .app) }
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
        formatter.locale = .app
        formatter.calendar = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: workoutDate(for: day))
    }

    // MARK: - Day management

    /// Schedules a workout the user already has on a date.
    ///
    /// Separate from `saveWorkout`, which writes the draft's chosen plan.
    /// There is no draft here: the template is
    /// known by id, so only a schedule row is written and the saved workout —
    /// its exercises, their relationship rows, their target sets — is left
    /// exactly as it was, wherever else it is also planned.
    ///
    /// Returns whether it was scheduled, so the caller can report the failure
    /// rather than closing as though it had worked.
    @discardableResult
    func scheduleKnownWorkout(_ summary: WorkoutSummary, on date: Date) async -> Bool {
        guard let repository else {
            persistenceError = SaveFailure.notConnected
            return false
        }
        guard !isSaving else {
            persistenceError = SaveFailure.alreadySaving
            return false
        }
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
            scheduleReads.invalidate()
            await reloadWeek(
                using: repository,
                generation: generation,
                showsLoadingState: false
            )
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            persistenceError = error.userFacingMessage
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
    /// else. Reusing a saved workout is explicit; its name alone never replaces
    /// the draft's selected exercises with another template's plan.
    func createTemplate(_ workout: Workout) async -> Int? {
        guard let repository else {
            persistenceError = SaveFailure.notConnected
            return nil
        }
        guard !isSaving else {
            persistenceError = SaveFailure.alreadySaving
            return nil
        }
        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil
        defer { if connectionGeneration == generation { isSaving = false } }

        do {
            let id = try await repository.createTemplate(Self.normalized(workout))
            guard connectionGeneration == generation else { return nil }
            // So the new workout is offered the next time a day is set, and
            // so the slot can name it without waiting for the next load.
            let reloaded = await reloadWeek(
                using: repository,
                generation: generation,
                showsLoadingState: false
            )
            guard reloaded, knownWorkouts.contains(where: { $0.serverID == id }) else {
                if connectionGeneration == generation, persistenceError == nil {
                    persistenceError = String(localized: "Your workout was saved, but could not be confirmed. Retry to reload it safely.", bundle: .app, locale: .app)
                }
                return nil
            }
            try await repository.acknowledgeTemplateSave(draftID: workout.id)
            guard connectionGeneration == generation else { return nil }
            await catalog.refreshMine()
            return id
        } catch {
            guard connectionGeneration == generation else { return nil }
            persistenceError = error.userFacingMessage
            return nil
        }
    }

    /// `nil` when it saved, and otherwise why it did not, for the editor to
    /// show instead of a sentence it made up. See `PlannerStore`'s equivalent.
    func saveWorkoutReportingFailure(_ workout: Workout, on day: Weekday) async -> String? {
        await saveWorkout(workout, on: day) ? nil : (persistenceError ?? SaveFailure.unexplained)
    }

    func saveWorkout(_ workout: Workout, on day: Weekday) async -> Bool {
        guard let repository else {
            persistenceError = SaveFailure.notConnected
            return false
        }
        guard !isSaving else {
            persistenceError = SaveFailure.alreadySaving
            return false
        }
        let generation = connectionGeneration
        // Only an edit of a workout already on this day replaces it; anything
        // else is scheduled alongside whatever is already planned.
        let existing = schedule[day]?.first { $0.id == workout.id }
        let date = dateString(for: day)
        let workout = Self.normalized(workout)
        isSaving = true
        persistenceError = nil
        lastSavedWorkoutID = nil

        defer { if connectionGeneration == generation { isSaving = false } }
        do {
            let templateID = try await repository.saveWorkout(
                workout,
                replacing: existing,
                scheduledDate: date
            )
            guard connectionGeneration == generation else { return false }
            scheduleReads.invalidate()
            let reloaded = await reloadWeek(
                using: repository,
                generation: generation,
                showsLoadingState: false
            )
            guard reloaded, let confirmed = schedule[day]?.first(where: {
                $0.serverID == templateID && $0.scheduledDate == date
            }) else {
                if connectionGeneration == generation, persistenceError == nil {
                    persistenceError = String(localized: "Your workout was saved, but could not be confirmed on this day. Retry to reload it safely.", bundle: .app, locale: .app)
                }
                return false
            }
            try await repository.acknowledgeTemplateSave(draftID: workout.id)
            guard connectionGeneration == generation else { return false }
            lastSavedWorkoutID = confirmed.id
            // A save can create exercises; Explore should offer them at once.
            await catalog.refreshMine()
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            persistenceError = error.userFacingMessage
            return false
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
                scheduleReads.invalidate()
                isLoading = false
                schedule[day]?.removeAll { $0.id == workout.id }
                if schedule[day]?.isEmpty == true {
                    schedule.removeValue(forKey: day)
                }
                calendarRevision &+= 1
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.userFacingMessage
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
                scheduleReads.invalidate()
                isLoading = false
                mutateWorkout(workout, on: day) { $0.recurrenceID = recurrenceID }
                calendarRevision &+= 1
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.userFacingMessage
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
        let candidate = WorkoutSelectionPolicy.resolve(requestedID: workoutID, in: workouts(on: day))
        if workoutID != nil, candidate == nil {
            persistenceError = String(localized: "This workout is no longer scheduled on this day. Reload the day and choose it again.", bundle: .app, locale: .app)
            return
        }
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
                routeTracker.reset()
                activeSession = session
                if checkpointActiveSession() { try await repository.acknowledgeSessionStart(id: session.serverID) }
                guard connectionGeneration == generation else { return }
                routeSummary = nil
                completedRoute = []
                previousSets = [:]
                // Only an activity that moves from place to place records a
                // track -- a run or a ride, not a pool, a court or a mat --
                // and only for as long as its session is active.
                if session.activity.tracksRoute {
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
                persistenceError = error.userFacingMessage
            }
            if connectionGeneration == generation { isSaving = false }
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
        guard !pendingSetIDs.contains(setID) else { return }
        mutateSet(on: day, exerciseID: exerciseID, setID: setID) { set in
            if let weightKilograms {
                set.weightKilograms = NumberInput.latinDigits(weightKilograms)
            }
            if let reps {
                set.reps = NumberInput.latinDigits(reps)
            }
            if let distanceKilometers {
                set.distanceKilometers = NumberInput.latinDigits(distanceKilometers)
            }
        }
    }

    func toggleSessionSetLogged(
        on day: Weekday,
        exerciseID: Exercise.ID,
        setID: WorkoutSetDraft.ID
    ) {
        Task { await toggleSessionSetLoggedNow(on: day, exerciseID: exerciseID, setID: setID) }
    }

    /// Completes a set from its row's check, filling an empty field from the
    /// hint first.
    ///
    /// The hint -- the target, or what was lifted last time -- is printed in
    /// the empty field, so checking the row is a deliberate "I did what it
    /// says". Nothing is filled in until that tap: an untouched field still
    /// never pretends to be today's number.
    func completeSessionSet(on day: Weekday, exerciseID: Exercise.ID, setID: WorkoutSetDraft.ID) {
        Task { await completeSessionSetNow(on: day, exerciseID: exerciseID, setID: setID) }
    }

    func completeSessionSetNow(on day: Weekday, exerciseID: Exercise.ID, setID: WorkoutSetDraft.ID) async {
        guard let exercise = sessionExercise(on: day, id: exerciseID),
              let index = exercise.sets.firstIndex(where: { $0.id == setID }),
              !exercise.sets[index].isLogged else { return }
        let set = exercise.sets[index]
        let hint = previousSet(for: exercise, at: index)
        if set.reps.trimmingCharacters(in: .whitespaces).isEmpty,
           let reps = exercise.targetReps(for: set) ?? hint?.reps {
            updateSessionSet(on: day, exerciseID: exerciseID, setID: setID, reps: String(reps))
        }
        if set.weightKilograms.trimmingCharacters(in: .whitespaces).isEmpty,
           let weight = exercise.targetWeightKilograms(for: set) ?? hint?.weightKilograms.map({ "\($0)" }) {
            updateSessionSet(on: day, exerciseID: exerciseID, setID: setID, weightKilograms: weight)
        }
        await toggleSessionSetLoggedNow(on: day, exerciseID: exerciseID, setID: setID)
    }

    /// Whether checking this set would log it: it has reps of its own, or a
    /// hint to take them from.
    func canComplete(_ set: WorkoutSetDraft, in exercise: SessionExerciseDraft) -> Bool {
        guard set.isWeightValid else { return false }
        if set.areRepsValid { return true }
        guard set.reps.trimmingCharacters(in: .whitespaces).isEmpty,
              let index = exercise.sets.firstIndex(where: { $0.id == set.id }) else { return false }
        return exercise.targetReps(for: set) != nil || previousSet(for: exercise, at: index)?.reps != nil
    }

    func toggleSessionSetLoggedNow(
        on day: Weekday,
        exerciseID: Exercise.ID,
        setID: WorkoutSetDraft.ID
    ) async {
        guard let repository,
              !pendingSetIDs.contains(setID),
              let session = activeSession(on: day),
              let exercise = sessionExercise(on: day, id: exerciseID),
              let set = exercise.sets.first(where: { $0.id == setID }) else {
            return
        }
        let generation = connectionGeneration
        let workoutType = session.workoutType

        pendingSetIDs.insert(setID)
        persistenceError = nil
        do {
            defer { if connectionGeneration == generation { pendingSetIDs.remove(setID) } }
            do {
                if set.isLogged {
                    guard let entryID = set.serverID else {
                        throw APIServiceError.missingServerIdentifier(
                            String(localized: "Set entry", bundle: .app, locale: .app, comment: "Names what is missing in “%@ has not been saved to the server yet.”")
                        )
                    }
                    try await repository.unlogSet(id: entryID, sessionExerciseID: exercise.sessionExerciseID, setNumber: set.setNumber)
                    guard connectionGeneration == generation else { return }
                    mutateSet(on: day, exerciseID: exerciseID, setID: setID) {
                        $0.serverID = nil
                        $0.isLogged = false
                    }
                } else {
                    let logged = try await repository.logSet(
                        set,
                        sessionExerciseID: exercise.sessionExerciseID,
                        workoutType: workoutType
                    )
                    guard connectionGeneration == generation else { return }
                    let weight = logged.weightKilograms
                    let reps = logged.reps
                    let distance = logged.distanceKilometers
                    mutateSet(on: day, exerciseID: exerciseID, setID: setID) {
                        $0.serverID = logged.id
                        $0.isLogged = true
                        $0.weightKilograms = weight
                        $0.reps = reps
                        $0.distanceKilometers = distance
                    }
                    if !workoutType.tracksDistance {
                        advanceAfterLogging(exerciseID: exerciseID, on: day)
                    }
                    if weight != set.weightKilograms || reps != set.reps || distance != set.distanceKilometers {
                        persistenceError = String(
                            localized: "Your earlier set was saved. Its saved values are shown; unlog it first if you want to change them.",
                            bundle: .app,
                            locale: .app
                        )
                    }
                }
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.userFacingMessage
            }
        }
    }

    /// Adds a set at the end of an exercise. A new set copies the kind of the
    /// one before it unless told otherwise -- a fourth working set after three
    /// is far more common than a fourth that is suddenly a warm-up -- but a
    /// drop set is never copied: two in a row is a choice, not a habit.
    func addSessionSet(on day: Weekday, exerciseID: Exercise.ID, type: WorkoutSetType? = nil) {
        mutateSession(on: day) { session in
            guard let index = session.exercises.firstIndex(
                where: { $0.id == exerciseID }
            ) else {
                return
            }
            let previous = session.exercises[index].sets.last?.setType
            let kind = type ?? (previous == .drop ? .normal : previous ?? .normal)
            session.exercises[index].sets.append(
                WorkoutSetDraft(setNumber: session.exercises[index].nextSetNumber, setType: kind)
            )
        }
    }

    func removeLastSessionSet(on day: Weekday, exerciseID: Exercise.ID) {
        guard let exercise = sessionExercise(on: day, id: exerciseID),
              exercise.sets.count > 1,
              let lastSet = exercise.sets.last else {
            return
        }
        removeSessionSet(on: day, exerciseID: exerciseID, setID: lastSet.id)
    }

    /// Deletes one set, wherever it is in the exercise. A logged set's entry
    /// is removed from the server first; the row only goes once that is
    /// confirmed, so a failure leaves both where they were. The other sets
    /// keep their numbers -- they are the server's keys -- and their rows
    /// close up, because what a row shows is its place, not its number.
    func removeSessionSet(on day: Weekday, exerciseID: Exercise.ID, setID: WorkoutSetDraft.ID) {
        guard let repository,
              let exercise = sessionExercise(on: day, id: exerciseID),
              exercise.sets.count > 1,
              let doomed = exercise.sets.first(where: { $0.id == setID }),
              !pendingSetIDs.contains(doomed.id) else {
            return
        }

        let generation = connectionGeneration
        pendingSetIDs.insert(doomed.id)
        Task {
            defer { if connectionGeneration == generation { pendingSetIDs.remove(doomed.id) } }
            do {
                if let entryID = doomed.serverID {
                    try await repository.unlogSet(id: entryID, sessionExerciseID: exercise.sessionExerciseID, setNumber: doomed.setNumber)
                } else {
                    try await repository.removeUnconfirmedSet(sessionExerciseID: exercise.sessionExerciseID, setNumber: doomed.setNumber)
                }
                guard connectionGeneration == generation else { return }
                removeSessionSetRow(
                    on: day,
                    exerciseID: exerciseID,
                    setID: doomed.id
                )
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.userFacingMessage
            }
        }
    }

    /// Changes what a set is for. An unlogged set changes here and is sent
    /// when it is logged; a logged one is corrected on the server too, without
    /// unlogging it, so fixing a label never costs the set.
    func setSessionSetType(
        _ type: WorkoutSetType,
        on day: Weekday,
        exerciseID: Exercise.ID,
        setID: WorkoutSetDraft.ID
    ) {
        guard !pendingSetIDs.contains(setID),
              let set = sessionExercise(on: day, id: exerciseID)?.sets.first(where: { $0.id == setID }),
              set.setType != type else { return }
        let previousType = set.setType
        mutateSet(on: day, exerciseID: exerciseID, setID: setID) { $0.setType = type }
        guard set.isLogged, let entryID = set.serverID, let repository else { return }

        let generation = connectionGeneration
        pendingSetIDs.insert(setID)
        Task {
            defer { if connectionGeneration == generation { pendingSetIDs.remove(setID) } }
            do {
                try await repository.updateSetType(entryID: entryID, type: type)
            } catch {
                guard connectionGeneration == generation else { return }
                mutateSet(on: day, exerciseID: exerciseID, setID: setID) { $0.setType = previousType }
                persistenceError = error.userFacingMessage
            }
        }
    }

    // MARK: - Reshaping a session in progress
    //
    // Every change here applies to this session at once and to nothing else.
    // Whether it should also become the saved workout's plan is asked once,
    // when the session finishes, rather than after every edit.

    /// Exercises being added, so the sheet can show progress and refuse a
    /// second tap while the first is on its way.
    private(set) var addingExerciseNames: Set<String> = []

    /// Adds an exercise to the end of the session: a catalog choice, or a
    /// name the account has never used, which is created first.
    @discardableResult
    func addSessionExercise(_ exercise: Exercise, on day: Weekday) async -> Bool {
        guard let repository, let session = activeSession(on: day) else { return false }
        let key = exercise.name.lowercased()
        guard !addingExerciseNames.contains(key) else { return false }
        let generation = connectionGeneration
        addingExerciseNames.insert(key)
        persistenceError = nil
        defer { if connectionGeneration == generation { addingExerciseNames.remove(key) } }
        do {
            let added = try await repository.addSessionExercise(exercise, toSession: session.serverID)
            guard connectionGeneration == generation, activeSession?.serverID == session.serverID else { return false }
            let count = max(exercise.sets, 1)
            let types = exercise.plannedSetTypes
            mutateSession(on: day) { session in
                session.exercises.append(SessionExerciseDraft(
                    id: UUID(),
                    exerciseServerID: added.exerciseID,
                    sessionExerciseID: added.sessionExerciseID,
                    name: added.name,
                    sets: (1...count).map {
                        WorkoutSetDraft(setNumber: $0, setType: types.indices.contains($0 - 1) ? types[$0 - 1] : .normal)
                    },
                    restSeconds: exercise.restSeconds,
                    targetReps: exercise.targetReps,
                    targetWeightKilograms: exercise.targetWeightKilograms
                ))
                if session.exercises.allSatisfy({ $0.isComplete || $0.id == session.exercises.last?.id }) {
                    session.focusedExerciseID = session.exercises.last?.id
                }
            }
            if added.created { await catalog.refreshMine() }
            // Hints for an exercise trained in some other workout. Quietly,
            // like the first read: it is a hint, not the session.
            if previousSets[added.exerciseID] == nil,
               let loaded = try? await repository.previousSets(excludingSessionID: session.serverID),
               connectionGeneration == generation {
                previousSets = loaded
            }
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            persistenceError = error.userFacingMessage
            return false
        }
    }

    /// Takes an exercise out of the session, with any sets already logged in
    /// it. The view asks first when there are; this does what it is told.
    func removeSessionExercise(on day: Weekday, exerciseID: Exercise.ID) async {
        guard let repository,
              let exercise = sessionExercise(on: day, id: exerciseID),
              !exercise.sets.contains(where: { pendingSetIDs.contains($0.id) }) else { return }
        let generation = connectionGeneration
        exercise.sets.forEach { pendingSetIDs.insert($0.id) }
        defer { if connectionGeneration == generation { exercise.sets.forEach { pendingSetIDs.remove($0.id) } } }
        persistenceError = nil
        do {
            try await repository.removeSessionExercise(id: exercise.sessionExerciseID)
            guard connectionGeneration == generation else { return }
            mutateSession(on: day) { session in
                guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
                session.exercises.remove(at: index)
                if session.focusedExerciseID == exerciseID {
                    session.focusedExerciseID = session.exercises.first { !$0.isComplete }?.id
                        ?? session.exercises.first?.id
                }
                // A superset of one is just an exercise.
                Self.dissolveLoneSupersets(in: &session)
            }
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.userFacingMessage
        }
    }

    /// Moves exercises within the session. The order changes here at once;
    /// the server is told behind it, and asked again at Finish if that did
    /// not get through. Sets, logged or not, travel with their exercise, and
    /// a rest in progress keeps counting.
    func moveSessionExercises(on day: Weekday, fromOffsets source: IndexSet, toOffset destination: Int) {
        mutateSession(on: day) { session in
            // The same rule as a SwiftUI list's move: `destination` is an
            // offset in the list as it was, before anything was taken out.
            let moving = source.sorted().map { session.exercises[$0] }
            var remaining = session.exercises.enumerated()
                .filter { !source.contains($0.offset) }
                .map(\.element)
            let insertion = destination - source.filter { $0 < destination }.count
            remaining.insert(contentsOf: moving, at: min(max(insertion, 0), remaining.count))
            guard remaining.map(\.id) != session.exercises.map(\.id) else { return }
            session.exercises = remaining
            session.orderNeedsSync = true
        }
        Task { await syncSessionOrder() }
    }

    private func syncSessionOrder() async {
        guard let repository, let session = activeSession, session.orderNeedsSync else { return }
        let generation = connectionGeneration
        let order = session.exercises.map(\.sessionExerciseID)
        do {
            try await repository.reorderSessionExercises(sessionID: session.serverID, sessionExerciseIDs: order)
            guard connectionGeneration == generation,
                  activeSession?.exercises.map(\.sessionExerciseID) == order else { return }
            mutateActiveSession { $0.orderNeedsSync = false }
        } catch {
            // Kept flagged and tried again at Finish. The order on this
            // screen is already right; only the saved record would differ.
        }
    }

    /// Seconds to rest after each set of this exercise, for this session.
    /// Nil returns it to the default. A rest already running is left alone.
    func setSessionRest(on day: Weekday, exerciseID: Exercise.ID, seconds: Int?) {
        mutateSession(on: day) { session in
            guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            session.exercises[index].restSeconds = seconds.map { min(max($0, 0), Int(RestTimer.maximumSeconds)) }
        }
    }

    /// Joins two exercises into a superset, or adds one to its partner's
    /// existing superset.
    func supersetSessionExercise(on day: Weekday, exerciseID: Exercise.ID, with partnerID: Exercise.ID) {
        guard exerciseID != partnerID else { return }
        mutateSession(on: day) { session in
            guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let partner = session.exercises.firstIndex(where: { $0.id == partnerID }) else { return }
            let group = session.exercises[partner].supersetGroup
                ?? session.exercises[index].supersetGroup
                ?? ((session.exercises.compactMap(\.supersetGroup).max() ?? 0) + 1)
            session.exercises[index].supersetGroup = group
            session.exercises[partner].supersetGroup = group
        }
    }

    func removeFromSuperset(on day: Weekday, exerciseID: Exercise.ID) {
        mutateSession(on: day) { session in
            guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            session.exercises[index].supersetGroup = nil
            Self.dissolveLoneSupersets(in: &session)
        }
    }

    private static func dissolveLoneSupersets(in session: inout ActiveWorkoutSession) {
        let counts = Dictionary(grouping: session.exercises.compactMap(\.supersetGroup), by: { $0 }).mapValues(\.count)
        for index in session.exercises.indices {
            if let group = session.exercises[index].supersetGroup, counts[group, default: 0] < 2 {
                session.exercises[index].supersetGroup = nil
            }
        }
    }

    /// Which exercise the screen and the Lock Screen point at. Switching never
    /// logs, unlogs or resets anything.
    func focusSessionExercise(_ exerciseID: Exercise.ID) {
        mutateActiveSession { session in
            guard session.exercises.contains(where: { $0.id == exerciseID }) else { return }
            session.focusedExerciseID = exerciseID
        }
    }

    /// The exercise to work on now: the chosen one while it still exists,
    /// otherwise the first with a set left.
    func focusedExercise(in session: ActiveWorkoutSession) -> SessionExerciseDraft? {
        if let id = session.focusedExerciseID, let chosen = session.exercises.first(where: { $0.id == id }) {
            return chosen
        }
        return session.exercises.first { !$0.isComplete } ?? session.exercises.first
    }

    /// Decides what happens once a set is in: start the rest, go to the next
    /// exercise of a superset, or carry straight on into a drop set.
    ///
    /// Logging a set always ends a rest still showing from before -- the
    /// person is plainly not resting -- and only a logged set starts one, so
    /// moving between exercises, editing or reordering never resets it.
    private func advanceAfterLogging(exerciseID: Exercise.ID, on day: Weekday) {
        guard let session = activeSession(on: day) else { return }
        let progress = session.exercises.map {
            WorkoutSetPolicy.ExerciseProgress(
                id: $0.id,
                supersetGroup: $0.supersetGroup,
                pendingTypes: $0.sets.filter { !$0.isLogged }.map(\.setType),
                loggedCount: $0.loggedCount,
                restSeconds: $0.restSeconds
            )
        }
        let decision = WorkoutSetPolicy.afterLogging(
            exerciseID: exerciseID,
            exercises: progress,
            defaultRestSeconds: preferences.defaultRestSeconds,
            autoStartRest: preferences.autoStartRest
        )
        mutateSession(on: day) { session in
            session.restTimer = nil
            switch decision {
            case .rest(let seconds, let focus):
                session.restTimer = .start(seconds: TimeInterval(seconds), exerciseID: exerciseID)
                if let focus { session.focusedExerciseID = focus }
            case .move(let next):
                session.focusedExerciseID = next
            case .stay(let focus):
                if let focus { session.focusedExerciseID = focus }
            }
        }
    }

    // MARK: - Rest timer

    /// Starts a rest by hand, for somebody whose timer does not start itself
    /// or who wants one between exercises.
    func startRest(seconds: Int, exerciseID: Exercise.ID? = nil) {
        guard seconds > 0 else { return }
        mutateActiveSession { session in
            session.restTimer = .start(
                seconds: TimeInterval(seconds),
                exerciseID: exerciseID ?? session.focusedExerciseID
            )
        }
    }

    func pauseRest() { mutateActiveSession { $0.restTimer?.pause() } }
    func resumeRest() { mutateActiveSession { $0.restTimer?.resume() } }

    func toggleRestPause() {
        mutateActiveSession { session in
            guard var timer = session.restTimer else { return }
            switch timer.phase() {
            case .running: timer.pause()
            case .paused: timer.resume()
            case .finished: return
            }
            session.restTimer = timer
        }
    }

    /// Ends the rest now. Also how a finished rest is cleared away.
    func skipRest() { mutateActiveSession { $0.restTimer = nil } }

    /// Starts the same rest again from its full length.
    func resetRest() { mutateActiveSession { $0.restTimer?.reset() } }

    func adjustRest(by seconds: TimeInterval) {
        mutateActiveSession { $0.restTimer?.adjust(by: seconds) }
    }

    // MARK: - Lock Screen

    /// Runs a tap from the Lock Screen or Dynamic Island.
    ///
    /// The intent wakes this process if it was suspended, and may have
    /// launched it. A launched app restores its session from the checkpoint
    /// once its account reconnects, so this waits a little for that before
    /// deciding there is nothing to act on. Every action names the session
    /// and the rest or set it was drawn for, so a stale button cannot act on
    /// whatever happens to be current now.
    func handleLiveActivityAction(_ action: WorkoutActivityAction) async {
        for _ in 0..<40 where activeSession == nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard let session = activeSession, session.serverID == action.sessionID else {
            await liveActivity.applyWithoutSession(action)
            return
        }
        switch action {
        case .completeSet(_, let exerciseID, let setID):
            await completeSessionSetNow(on: session.day, exerciseID: exerciseID, setID: setID)
        case .toggleRest(_, let restID):
            guard session.restTimer?.id == restID else { return }
            toggleRestPause()
        case .skipRest(_, let restID):
            guard session.restTimer?.id == restID else { return }
            skipRest()
        case .addRest(_, let restID, let seconds):
            guard session.restTimer?.id == restID else { return }
            adjustRest(by: TimeInterval(seconds))
        }
        await liveActivity.flush()
    }

    // MARK: - Saving today's shape as the plan

    /// Makes the saved workout match this session's exercises, order, sets,
    /// set kinds, rests and supersets. Asked for at Finish, never assumed.
    ///
    /// Exercises the plan already had keep their saved rows, and with them
    /// their targets; new ones are added and dropped ones removed. Weights and
    /// reps are not copied into targets: they are what happened today, not a
    /// decision about every session after it.
    @discardableResult
    func saveStructureAsPlan(_ session: ActiveWorkoutSession) async -> Bool {
        guard let repository else {
            persistenceError = SaveFailure.notConnected
            return false
        }
        let generation = connectionGeneration
        let supersets = WorkoutStructureDiff.normalizedSupersets(session.exercises.map(\.supersetGroup))
        let plan = zip(session.exercises, supersets).map { exercise, superset in
            Exercise(
                serverID: exercise.exerciseServerID,
                workoutExerciseID: exercise.workoutExerciseID,
                serverName: exercise.name,
                name: exercise.name,
                sets: exercise.sets.count,
                setTypes: WorkoutStructureDiff.storedSetTypes(exercise.sets.map(\.setType)),
                restSeconds: exercise.restSeconds,
                supersetGroup: superset,
                targetReps: exercise.targetReps,
                targetWeightKilograms: exercise.targetWeightKilograms
            )
        }
        do {
            try await repository.replacePlan(workoutID: session.workoutServerID, exercises: plan)
            guard connectionGeneration == generation else { return false }
            scheduleReads.invalidate()
            await reloadWeek(using: repository, generation: generation, showsLoadingState: false)
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            persistenceError = String(
                localized: "Your workout is saved, but its plan could not be updated. \(error.userFacingMessage ?? error.localizedDescription)",
                bundle: .app,
                locale: .app
            )
            return false
        }
    }

    /// Finishes the session. `updatingPlan` is the answer to "make this the
    /// saved workout's plan?", asked by the screen only when the session was
    /// reshaped; it is applied after the finish is confirmed, so a failure to
    /// update the plan can never cost the workout itself.
    func endSession(on day: Weekday, updatingPlan: Bool = false) async -> Int? {
        if activeSession?.orderNeedsSync == true { await syncSessionOrder() }
        guard let repository,
              let session = activeSession,
              session.day == day,
              pendingSetIDs.isEmpty,
              !isSaving, !isRecoveringWorkouts else {
            return nil
        }

        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil
        defer {
            if connectionGeneration == generation { isSaving = false }
        }
        let result = await finish(session, using: repository, generation: generation)
        if result != nil, updatingPlan, !session.structureChanges.isEmpty, connectionGeneration == generation {
            isSaving = false
            await saveStructureAsPlan(session)
        }
        return result
    }

    private func finish(
        _ session: ActiveWorkoutSession,
        using repository: WorkoutAPIRepository,
        generation: UUID
    ) async -> Int? {
        do {
            let statsBeforeCompletion = trainingStats
            guard let ownerID = recoveryOwnerID else {
                persistenceError = String(localized: "Reconnect before finishing this workout.", bundle: .app, locale: .app)
                return nil
            }
            // Write the finish intent before the first network request. A disk
            // failure leaves the route in memory and does not pretend it is safe.
            let recorded = routeTracker.stopTracking()
            let existing = try recovery.entries(ownerID: ownerID, origin: recoveryOrigin)
                .first { $0.sessionID == session.serverID }
            let pending = existing ?? PendingWorkoutSave(
                id: UUID(), ownerID: ownerID, origin: recoveryOrigin,
                sessionID: session.serverID, workoutName: session.workoutName,
                requestedAt: Date(), points: session.tracksDistance ? recorded : []
            )
            try recovery.put(pending)
            refreshPendingWorkoutCount()
            try await transmitPendingWorkout(pending, using: repository, generation: generation)
            guard connectionGeneration == generation else { return nil }
            completedSessions.append(
                CompletedWorkoutSession(session: session, endedAt: pending.requestedAt)
            )
            activeSession = nil
            routeTracker.reset()

            // Keep the dashboard current when the user returns from the
            // finished session. The totals are the server's, so this asks for
            // them again rather than re-deriving them from a full history
            // download, and the badge window stays bounded.
            if let stats = try? await repository.trainingStats() {
                guard connectionGeneration == generation else { return nil }
                trainingStats = stats
            }
            if let refreshed = try? await repository.completedSessions(
                since: Calendar.current.date(
                    byAdding: .day,
                    value: -Self.badgeHistoryDays,
                    to: Date()
                )
            ) {
                guard connectionGeneration == generation else { return nil }
                dashboardSessions = refreshed
            }

            guard connectionGeneration == generation else { return nil }
            if session.loggedSetCount > 0 {
                pendingTrainingDashboardReward = TrainingDashboardReward(
                    workoutName: session.workoutName,
                    day: session.day,
                    previousCompletedThisWeek: statsBeforeCompletion.completedThisWeek,
                    completedThisWeek: trainingStats.completedThisWeek,
                    previousTotalWorkouts: statsBeforeCompletion.totalWorkouts,
                    totalWorkouts: trainingStats.totalWorkouts
                )
            }

            // Load what the summary needs. A failure here costs only the
            // chart or the record list, so the finished workout is still
            // reported as saved either way.
            if session.tracksDistance {
                let history = (try? await repository.sessionHistory(
                    workoutName: session.workoutName
                )) ?? []
                guard connectionGeneration == generation else { return nil }
                sessionHistory = history
            } else {
                let records = (try? await repository.personalRecords(
                    sessionID: session.serverID
                )) ?? []
                guard connectionGeneration == generation else { return nil }
                personalRecords = records

                var progress: [LiftProgressSeries] = []
                for exercise in session.exercises {
                    if let series = try? await repository.liftProgress(
                        exerciseID: exercise.exerciseServerID,
                        exerciseName: exercise.name,
                        workoutName: session.workoutName
                    ), series.hasEnoughToPlot {
                        guard connectionGeneration == generation else { return nil }
                        progress.append(series)
                    }
                }
                guard connectionGeneration == generation else { return nil }
                liftProgress = progress
            }

            return session.loggedSetCount
        } catch {
            guard connectionGeneration == generation else { return nil }
            persistenceError = String(
                localized: "Workout has not fully synced. Keep this screen open and tap Finish to retry, or retry from Training after reopening. \(error.userFacingMessage ?? error.localizedDescription)",
                bundle: .app,
                locale: .app
            )
            recoveryError = persistenceError
            return nil
        }
    }

    // MARK: - Activities logged afterwards

    /// Saves an activity that already happened -- a tennis match, a hike --
    /// to this day's history in one request. The server files it under the
    /// workout of that name (making one if there is none), puts that workout
    /// on the day, and records the session as finished. Answers a problem to
    /// show, or nil once it is saved and the day and the totals show it.
    func logActivity(_ entry: ActivityLogEntry, on day: Weekday, workoutServerID: Int? = nil) async -> String? {
        guard let repository else { return SaveFailure.notConnected }
        let generation = connectionGeneration
        persistenceError = nil
        do {
            _ = try await repository.logActivity(
                entry,
                workoutServerID: workoutServerID,
                scheduledDate: Self.dateString(workoutDate(for: day))
            )
            guard generation == connectionGeneration else { return nil }
            scheduleReads.invalidate()
            await reloadWeek(using: repository, generation: generation, showsLoadingState: false)
            await refreshTrainingHistory(using: repository, generation: generation)
            return nil
        } catch {
            guard generation == connectionGeneration else { return nil }
            return error.userFacingMessage ?? error.localizedDescription
        }
    }

    /// Saves "how did it feel" onto a session that has finished. The values
    /// are the person's own; a distance is only sent where nothing measured
    /// one.
    func saveSessionFeedback(_ feedback: SessionFeedback, sessionID: Int) async -> String? {
        guard let repository else { return SaveFailure.notConnected }
        let generation = connectionGeneration
        do {
            let saved = try await repository.saveSessionFeedback(feedback, sessionID: sessionID)
            guard generation == connectionGeneration else { return nil }
            // A server from before effort existed answers 200 and keeps none
            // of it. Saying "saved" then would be untrue.
            guard saved else {
                return String(localized: "Your Rytivo server doesn’t store effort yet. Update the server, then try again.", bundle: .app, locale: .app)
            }
            await refreshTrainingHistory(using: repository, generation: generation)
            return nil
        } catch {
            guard generation == connectionGeneration else { return nil }
            return error.userFacingMessage ?? error.localizedDescription
        }
    }

    /// The totals and the recent sessions, read again after something was
    /// added to them. Quietly: a failure leaves what was shown.
    private func refreshTrainingHistory(using repository: WorkoutAPIRepository, generation: UUID) async {
        if let stats = try? await repository.trainingStats(), generation == connectionGeneration {
            trainingStats = stats
        }
        if let refreshed = try? await repository.completedSessions(
            since: Calendar.current.date(byAdding: .day, value: -Self.badgeHistoryDays, to: Date())
        ), generation == connectionGeneration {
            dashboardSessions = refreshed
        }
    }

    /// Hands a completion reward to Training exactly once. Waiting for the
    /// dashboard to consume it prevents confetti and progress motion from
    /// playing underneath the completion screen where nobody can see them.
    func consumeTrainingDashboardReward() -> TrainingDashboardReward? {
        defer { pendingTrainingDashboardReward = nil }
        return pendingTrainingDashboardReward
    }

    /// Deletes the session in progress and everything logged in it.
    ///
    /// Asked for after a confirmation, so it does what it is told -- but it
    /// says when it cannot, rather than returning quietly and leaving the
    /// workout open with no explanation, which is how a started workout used
    /// to look impossible to delete. A session the server no longer has is
    /// already gone, so that counts as done: the phone must not hold on to a
    /// workout nothing else knows about. The Lock Screen activity and the
    /// rest notification go with it, because both follow `activeSession`.
    @discardableResult
    func discardSession(on day: Weekday) async -> Bool {
        guard let session = activeSession, session.day == day else { return false }
        guard let repository else {
            persistenceError = String(localized: "Reconnect to delete this workout. Nothing has been deleted.", bundle: .app, locale: .app)
            return false
        }
        guard pendingSetIDs.isEmpty, !isSaving else {
            persistenceError = String(localized: "A set is still saving. Try again in a moment.", bundle: .app, locale: .app)
            return false
        }

        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil
        defer { if connectionGeneration == generation { isSaving = false } }
        do {
            do {
                try await repository.discardSession(id: session.serverID)
            } catch APIServiceError.undocumentedStatus(404) {
                // Already deleted, from another device or by a retry whose
                // first answer was lost.
            }
            guard connectionGeneration == generation else { return false }
            if let ownerID = recoveryOwnerID {
                do {
                    try recovery.discardSession(ownerID: ownerID, origin: recoveryOrigin, sessionID: session.serverID)
                } catch {
                    recoveryError = String(localized: "Workout discarded. Local recovery cleanup needs another attempt.", bundle: .app, locale: .app)
                }
                refreshPendingWorkoutCount()
            }
            activeSession = nil
            // A discarded session keeps no track.
            clearActiveCheckpoint(sessionID: session.serverID)
            routeTracker.reset()
            routeSummary = nil
            completedRoute = []
            previousSets = [:]
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            persistenceError = String(
                localized: "Couldn’t delete this workout, so it’s still open and nothing was lost. \(error.userFacingMessage ?? error.localizedDescription)",
                bundle: .app,
                locale: .app
            )
            return false
        }
    }

    @discardableResult
    func checkpointActiveSession(force: Bool = true) -> Bool {
        guard let session = activeSession, let ownerID = recoveryOwnerID else { return false }
        guard force || Date().timeIntervalSince(lastCheckpointAt) >= 5 else { return false }
        do {
            try EditorDraftRecovery.shared.save(ActiveCheckpoint(session: session, points: routeTracker.points),
                key: "active-workout", scope: .init(ownerID: ownerID, origin: recoveryOrigin))
            lastCheckpointAt = Date()
            return true
        } catch {
            recoveryError = String(localized: "Couldn't checkpoint this session locally. \(error.localizedDescription)", bundle: .app, locale: .app)
            return false
        }
    }

    private func clearActiveCheckpoint(sessionID: Int) {
        guard let ownerID = recoveryOwnerID else { return }
        let scope = EditorDraftRecovery.Scope(ownerID: ownerID, origin: recoveryOrigin)
        do {
            if let saved = try EditorDraftRecovery.shared.load(ActiveCheckpoint.self, key: "active-workout", scope: scope),
               saved.session.serverID == sessionID {
                try EditorDraftRecovery.shared.remove(key: "active-workout", scope: scope)
            }
            recoveredActiveSession = false
        } catch { recoveryError = String(localized: "Session saved, but its local checkpoint needs cleanup.", bundle: .app, locale: .app) }
    }

    private func restoreActiveCheckpoint(using repository: WorkoutAPIRepository, generation: UUID) async {
        guard activeSession == nil, let ownerID = recoveryOwnerID else { return }
        let scope = EditorDraftRecovery.Scope(ownerID: ownerID, origin: recoveryOrigin)
        do {
            guard let saved = try EditorDraftRecovery.shared.load(ActiveCheckpoint.self, key: "active-workout", scope: scope) else {
                if let recovered = try await repository.recoverPendingSessionStart(),
                   generation == connectionGeneration, activeSession == nil {
                    routeTracker.reset()
                    activeSession = recovered
                    recoveredActiveSession = true
                    if checkpointActiveSession() { try await repository.acknowledgeSessionStart(id: recovered.serverID) }
                    // As startSession does: the hints and one-tap logging
                    // read last time's sets, and a relaunch had lost them.
                    if !recovered.tracksDistance {
                        await loadPreviousSets(for: recovered, using: repository, generation: generation)
                    }
                }
                return
            }
            if try recovery.entries(ownerID: ownerID, origin: recoveryOrigin).contains(where: { $0.sessionID == saved.session.serverID }) { return }
            let isActive = try await repository.isSessionActive(id: saved.session.serverID)
            guard generation == connectionGeneration, activeSession == nil else { return }
            guard isActive else {
                clearActiveCheckpoint(sessionID: saved.session.serverID)
                try await repository.acknowledgeSessionStart(id: saved.session.serverID)
                return
            }
            let reconciled = try await repository.reconcileLoggedSets(saved.session)
            guard generation == connectionGeneration, activeSession == nil else { return }
            routeTracker.restore(saved.points)
            activeSession = reconciled
            recoveredActiveSession = true
            if checkpointActiveSession() { try await repository.acknowledgeSessionStart(id: reconciled.serverID) }
            if !reconciled.tracksDistance {
                await loadPreviousSets(for: reconciled, using: repository, generation: generation)
            }
        } catch {
            guard generation == connectionGeneration else { return }
            recoveryError = String(
                localized: "Your session checkpoint is kept, but couldn't be reopened. \(error.userFacingMessage ?? error.localizedDescription)",
                bundle: .app,
                locale: .app
            )
        }
    }

    func resumeRecoveredTracking() {
        guard recoveredActiveSession, activeSession?.activity.tracksRoute == true else { return }
        routeTracker.startTracking(preservingPoints: true)
        if routeTracker.isTracking { recoveredActiveSession = false }
    }

    func refreshPendingWorkoutCount() {
        guard let ownerID = recoveryOwnerID else { return }
        do {
            pendingWorkoutSaveCount = try recovery.entries(ownerID: ownerID, origin: recoveryOrigin).count
        } catch { recoveryError = String(localized: "Couldn't read locally saved workouts. \(error.localizedDescription)", bundle: .app, locale: .app) }
    }

    func deleteAccountRecovery(ownerID: Int, origin: String) {
        do { try recovery.removeAccount(ownerID: ownerID, origin: origin) }
        catch { recoveryError = String(localized: "Local recovery data could not be removed. \(error.localizedDescription)", bundle: .app, locale: .app) }
    }

    private func transmitPendingWorkout(
        _ pending: PendingWorkoutSave, using repository: WorkoutAPIRepository, generation: UUID
    ) async throws {
        for offset in stride(from: 0, to: pending.points.count, by: 1000) {
            guard generation == connectionGeneration, !Task.isCancelled else { throw CancellationError() }
            let batch = Array(pending.points[offset..<min(offset + 1000, pending.points.count)])
            let summary = try await repository.uploadRoute(batch, sessionID: pending.sessionID)
            guard generation == connectionGeneration, !Task.isCancelled else { throw CancellationError() }
            routeSummary = summary
        }
        guard generation == connectionGeneration, !Task.isCancelled else { throw CancellationError() }
        try await repository.endSession(id: pending.sessionID, endedAt: pending.requestedAt)
        guard generation == connectionGeneration else { throw CancellationError() }
        // Finishing also completes the server's planner task. Both a live
        // Finish and an offline-recovery retry use this path. Local cleanup
        // failure must not hide an already confirmed server-side completion.
        calendarRevision &+= 1
        guard !Task.isCancelled else { throw CancellationError() }
        // Both operations are retry-safe; even a failed local delete can retry.
        try recovery.remove(pending)
        clearActiveCheckpoint(sessionID: pending.sessionID)
        refreshPendingWorkoutCount()
        recoveryError = nil
    }

    func retryPendingWorkoutSaves() async {
        guard let repository, let ownerID = recoveryOwnerID,
              !isSaving, !isRecoveringWorkouts else { return }
        let generation = connectionGeneration
        isRecoveringWorkouts = true
        recoveryError = nil
        defer { if generation == connectionGeneration { isRecoveringWorkouts = false } }
        do {
            let pending = try recovery.entries(ownerID: ownerID, origin: recoveryOrigin)
            pendingWorkoutSaveCount = pending.count
            var syncedAny = false
            var lastFailure: String?
            for item in pending {
                // A live screen must consume its own completion once, via Finish.
                if activeSession?.serverID == item.sessionID { continue }
                do {
                    try await transmitPendingWorkout(item, using: repository, generation: generation)
                    syncedAny = true
                } catch {
                    guard generation == connectionGeneration, !Task.isCancelled else { return }
                    // Keep this record, but do not block recovery of other workouts.
                    lastFailure = error.userFacingMessage
                }
            }
            guard generation == connectionGeneration else { return }
            if let lastFailure {
                recoveryError = String(localized: "Workout sync is pending. Your local copy is kept. \(lastFailure)", bundle: .app, locale: .app)
            }
            if syncedAny { await loadDashboardSessions() }
            if activeSession == nil, generation == connectionGeneration {
                await restoreActiveCheckpoint(using: repository, generation: generation)
            }
        } catch {
            guard generation == connectionGeneration else { return }
            recoveryError = String(
                localized: "Workout sync is pending. Your local copy is kept. \(error.userFacingMessage ?? error.localizedDescription)",
                bundle: .app,
                locale: .app
            )
        }
    }

    // MARK: - Retry and mapping

    /// Reconnects and reloads. Callable whenever a repository exists, so a
    /// failed load can always be retried.
    /// Empties the schedule from today and reads the week back.
    ///
    /// Reloaded rather than emptied in place: the server decides what "from
    /// today" means in the user's own zone, and guessing here is how a day
    /// disappears on screen that is still booked on the server.
    func clearSchedule() async {
        guard let repository, !isSaving else { return }
        let generation = connectionGeneration
        isSaving = true
        defer { if connectionGeneration == generation { isSaving = false } }

        do {
            try await repository.clearSchedule()
            guard connectionGeneration == generation else { return }
            scheduleReads.invalidate()
            await reloadWeek(
                using: repository,
                generation: generation,
                showsLoadingState: false
            )
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.userFacingMessage
        }
    }

    /// Deletes a saved workout, and everything planned from it.
    ///
    /// The week is read again afterwards rather than patched: the days this
    /// workout occupied are gone on the server, and working out which of them
    /// were on screen is more effort than asking.
    func deleteSavedWorkout(_ workout: WorkoutSummary) async {
        guard let repository, !isSaving else { return }
        let generation = connectionGeneration
        isSaving = true
        defer { if connectionGeneration == generation { isSaving = false } }

        do {
            try await repository.deleteSavedWorkout(id: workout.id)
            guard connectionGeneration == generation else { return }
            scheduleReads.invalidate()
            knownWorkouts.removeAll { $0.id == workout.id }
            await reloadWeek(
                using: repository,
                generation: generation,
                showsLoadingState: false
            )
        } catch {
            guard connectionGeneration == generation else { return }
            // Shown rather than swallowed: the refusal names the rotation
            // standing in the way, which is the one thing that makes the
            // failure actionable.
            persistenceError = error.userFacingMessage
        }
    }

    // MARK: - The saved-workout library

    /// Saves changes to a library workout without putting it on a day. Days it
    /// is already planned on show the new plan, because they are that
    /// workout, not copies of it.
    func updateSavedWorkout(_ workout: Workout) async -> String? {
        guard let repository else { return SaveFailure.notConnected }
        guard !isSaving else { return SaveFailure.alreadySaving }
        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil
        defer { if connectionGeneration == generation { isSaving = false } }
        do {
            try await repository.updateTemplate(Self.normalized(workout))
            guard connectionGeneration == generation else { return SaveFailure.unexplained }
            scheduleReads.invalidate()
            await reloadWeek(using: repository, generation: generation, showsLoadingState: false)
            await catalog.refreshMine()
            return nil
        } catch {
            guard connectionGeneration == generation else { return SaveFailure.unexplained }
            persistenceError = error.userFacingMessage
            return persistenceError ?? SaveFailure.unexplained
        }
    }

    /// Makes a copy of a saved workout under a free name, "Push Day copy",
    /// "Push Day copy 2" and so on. Names are unique per account, so the
    /// first free one is chosen here rather than refused by the server.
    @discardableResult
    func duplicateSavedWorkout(_ summary: WorkoutSummary) async -> Int? {
        let taken = Set(knownWorkouts.map { $0.name.lowercased() })
        let base = String(localized: "\(summary.name) copy", bundle: .app, locale: .app, comment: "The name of a copied workout; the placeholder is the original's name")
        var name = base
        var number = 2
        while taken.contains(name.lowercased()) {
            name = "\(base) \(number)"
            number += 1
        }
        var copy = summary.asWorkout
        copy = Workout(
            name: String(name.prefix(150)),
            type: copy.type,
            activity: copy.activity,
            cardioMachine: copy.cardioMachine,
            cardioTargetMinutes: copy.cardioTargetMinutes,
            // New rows for the copy: sharing the original's would edit it.
            exercises: copy.exercises.map {
                Exercise(
                    serverID: $0.serverID, serverName: $0.serverName, name: $0.name, sets: $0.sets,
                    setTypes: $0.setTypes, restSeconds: $0.restSeconds, supersetGroup: $0.supersetGroup,
                    targetReps: $0.targetReps, targetWeightKilograms: $0.targetWeightKilograms
                )
            }
        )
        return await createTemplate(copy)
    }

    /// Starts a saved workout today: it is put on today first if it is not
    /// already there, then started. Answers with the day to open.
    func startSavedWorkout(_ summary: WorkoutSummary) async -> Weekday? {
        guard let today else { return nil }
        if workouts(on: today).first(where: { $0.serverID == summary.serverID }) == nil {
            guard await scheduleKnownWorkout(summary, on: workoutDate(for: today)) else { return nil }
        }
        guard let scheduled = workouts(on: today).first(where: { $0.serverID == summary.serverID }) else {
            persistenceError = String(localized: "This workout is no longer scheduled on this day. Reload the day and choose it again.", bundle: .app, locale: .app)
            return nil
        }
        if activeSession == nil { startSession(on: today, workoutID: scheduled.id) }
        return today
    }

    /// Whether there is anything planned to clear. Offering the button over an
    /// empty calendar would be offering to do nothing.
    var hasAnythingScheduled: Bool {
        schedule.values.contains { !$0.isEmpty }
    }

    /// Reads the visible week back from the server.
    ///
    /// For changes made somewhere other than this store. A rotation plans days
    /// by writing them on the server, and until they are read back the week on
    /// screen is the one from before it was started -- which reads as the
    /// rotation having quietly done nothing.
    func reloadSchedule() async {
        guard let repository else { return }
        await reloadWeek(
            using: repository,
            generation: connectionGeneration,
            showsLoadingState: false
        )
    }

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

    @discardableResult
    private func reloadWeek(
        using repository: WorkoutAPIRepository,
        generation: UUID,
        showsLoadingState: Bool
    ) async -> Bool {
        guard connectionGeneration == generation else { return false }
        let readID = scheduleReads.begin()
        if showsLoadingState { isLoading = true }
        // The flag is cleared no matter how this exits. Leaving it set after a
        // stale return would disable every editing control with nothing on
        // screen to explain why, and retryPersistence() would refuse to run.
        defer {
            if connectionGeneration == generation, scheduleReads.accepts(readID) {
                isLoading = false
                // Also on a failed week read: a preceding server write may
                // have succeeded, and the planner must independently refresh.
                calendarRevision &+= 1
            }
        }

        persistenceError = nil
        do {
            let loaded = try await repository.loadWeek(
                dateByDay: dateStringsForCurrentWeek()
            )
            guard connectionGeneration == generation, scheduleReads.accepts(readID) else { return false }
            schedule = loaded.schedule
            // Names to offer when creating a workout, built from the templates
            // the schedule was built from. This was a second sequential request
            // for rows the first one had already read.
            knownWorkouts = loaded.library
            return true
        } catch {
            guard connectionGeneration == generation, scheduleReads.accepts(readID) else { return false }
            persistenceError = error.userFacingMessage
            return false
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

    private func removeSessionSetRow(
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

    /// For changes that belong to whichever session is running -- its rest,
    /// its focus -- wherever they are made from.
    private func mutateActiveSession(_ mutation: (inout ActiveWorkoutSession) -> Void) {
        guard var session = activeSession else { return }
        mutation(&session)
        guard session != activeSession else { return }
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

        let generation = connectionGeneration
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
            guard connectionGeneration == generation else { return false }
            recordedCardioSeconds = seconds
            cardioSessionID = nil
            return true
        } catch {
            guard connectionGeneration == generation else { return false }
            // The time is kept on screen so it is not lost to a failed save.
            cardioStartedAt = startedAt
            persistenceError = String(localized: "Cardio could not be saved: \(error.localizedDescription)", bundle: .app, locale: .app)
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
        // Named in English whatever the interface language: the server finds
        // an exercise again by its name, so a translated one would start a
        // second exercise, and a second history, after a language change.
        // An activity saved before activities existed keeps the name its
        // history is under ("Biking", not "Cycling"); a newer one is named
        // after itself, so a hike's efforts are not filed as running.
        let label = workout.activity == .legacyDefault(for: workout.type)
            ? workout.type.rawValue.capitalized
            : workout.activity.rawValue.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        workout.exercises = [
            Exercise(name: label, sets: 1)
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
                exercises: workout.exercises,
                lastPerformedAt: index == 0 ? Date().addingTimeInterval(-3 * 86_400)
                    : index == 1 ? Date().addingTimeInterval(-9 * 86_400) : nil
            )
        }
        return store
    }

#if DEBUG
    /// A lifting session part way through: a warm-up and a working set in,
    /// a superset, a rest running, and an exercise added since the start.
    /// The live screen is several taps and a server away, which is out of a
    /// script's reach, so this is how it is looked at in the simulator.
    static var previewActiveSession: WorkoutStore {
        let store = previewWithLibrary
        let day = store.today ?? .monday
        let bench = UUID(), incline = UUID(), fly = UUID(), dips = UUID()
        func sets(_ types: [WorkoutSetType], logged: Int, weight: String, reps: String) -> [WorkoutSetDraft] {
            types.enumerated().map { index, type in
                WorkoutSetDraft(
                    serverID: index < logged ? 900 + index : nil,
                    setNumber: index + 1,
                    weightKilograms: index < logged ? weight : "",
                    reps: index < logged ? reps : "",
                    isLogged: index < logged,
                    setType: type
                )
            }
        }
        var session = ActiveWorkoutSession(
            id: UUID(), serverID: 4242, day: day, workoutID: UUID(), workoutServerID: 1,
            workoutName: "Upper Body", workoutType: .lifting,
            startedAt: Date().addingTimeInterval(-24 * 60),
            exercises: [
                SessionExerciseDraft(id: bench, exerciseServerID: 11, sessionExerciseID: 101, name: "Bench Press",
                                     sets: sets([.warmup, .normal, .normal, .normal, .drop], logged: 2, weight: "60", reps: "8"),
                                     workoutExerciseID: 1, restSeconds: 150, targetReps: 8),
                SessionExerciseDraft(id: incline, exerciseServerID: 12, sessionExerciseID: 102, name: "Incline Dumbbell Press",
                                     sets: sets([.normal, .normal, .normal], logged: 0, weight: "", reps: ""),
                                     workoutExerciseID: 2, supersetGroup: 1),
                SessionExerciseDraft(id: fly, exerciseServerID: 13, sessionExerciseID: 103, name: "Cable Fly",
                                     sets: sets([.normal, .normal, .failure], logged: 0, weight: "", reps: ""),
                                     workoutExerciseID: 3, supersetGroup: 1),
                SessionExerciseDraft(id: dips, exerciseServerID: 14, sessionExerciseID: 104, name: "Dips",
                                     sets: sets([.normal, .normal], logged: 0, weight: "", reps: ""))
            ],
            restTimer: .start(seconds: 150, exerciseID: bench, at: Date().addingTimeInterval(-38)),
            focusedExerciseID: bench
        )
        var plan = session.structure
        plan.items.removeLast()
        session.plan = plan
        store.previousSets = [
            11: [PreviousSet(setNumber: 1, weightKilograms: 40, reps: 10, setType: .warmup),
                 PreviousSet(setNumber: 2, weightKilograms: Decimal(string: "57.5"), reps: 8),
                 PreviousSet(setNumber: 3, weightKilograms: Decimal(string: "57.5"), reps: 7)],
            12: [PreviousSet(setNumber: 1, weightKilograms: 22, reps: 10)]
        ]
        store.activeSession = session
        return store
    }

    /// One instance for the launch flag. The app's root is rebuilt as it
    /// comes to the front, and a fresh store each time would hand the screen
    /// a session with new ids, which reads to it as a change of focus.
    static let sharedPreviewActiveSession = previewActiveSession
#endif
}
