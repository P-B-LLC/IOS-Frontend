//
//  ActivityStore.swift
//  IOS Frontend
//
//  Main-actor step state, read from the server and fed from Apple Health.
//
//  Two sources, one direction. Health is the only place steps come from, and
//  the server is the only place they are read back from. The device never
//  shows a Health reading directly: it sends what Health said, then draws what
//  the server stored, so the count here is the count everywhere.
//

import Foundation
import Observation

@Observable
@MainActor
final class ActivityStore {
    private var repository: ActivityAPIRepository?
    private let health: any HealthDataReading
    private let defaults: UserDefaults
    private var scope: HealthIntegrationScope?
    private var connectionGeneration = UUID()
    private var celebrationGate = StepGoalCelebrationGate()

    /// Days the server holds, newest first. The only thing the UI draws.
    private(set) var recentDays: [DailyStepCount] = []
    private(set) var isLoading = false
    private(set) var isSyncing = false
    private(set) var persistenceError: String?
    /// What the last import brought in, or nil before one has run.
    private(set) var lastImport: HealthImportSummary?
    /// When the device last completed a Health-to-server refresh.
    private(set) var lastSyncedAt: Date?
    private(set) var serverHealthSyncEnabled = false
    private(set) var isIntegrationSupported: Bool?
    private(set) var isLoadingIntegration = false
    private(set) var isHealthPausePending = false
    private(set) var wearableWorkouts: [HealthWorkoutSummary] = []
    private(set) var isLoadingWorkouts = false
    private(set) var garminWorkouts: [HealthWorkoutSummary] = []
    private(set) var isLoadingGarminWorkouts = false
    private var nextGarminPage: Int?
    private var visitedGarminPages: Set<Int> = []
    private var hasLoadedGarmin = false
    private var nextWorkoutPage: Int?
    private var visitedWorkoutPages: Set<Int> = []
    private var lastSyncAttemptAt: Date?
    /// A single refresh after the complete import, never one per sample.
    var onWorkoutsChanged: (() async -> Void)?

    var hasMoreWorkouts: Bool { nextWorkoutPage != nil }
    var hasMoreGarminWorkouts: Bool { nextGarminPage != nil }
    var healthSyncEnabled: Bool {
        guard let scope else { return false }
        return serverHealthSyncEnabled && isIntegrationSupported == true
            && defaults.bool(forKey: scope.preferenceKey)
    }

    /// How far back the widget reads and sends.
    ///
    /// A week, because that is what the strip shows. Health keeps far more,
    /// but importing all of it on every launch would send thousands of days
    /// nobody is looking at.
    static let historyDays = 7

    /// How far back workouts are offered to the server.
    ///
    /// Longer than the step window because a missed workout matters for longer
    /// than a missed day's steps, and because the server recognises anything it
    /// has already taken: sending a month costs a few rows it will ignore, and
    /// buys back any week the app was not opened.
    static let importHorizonDays = 30

    /// Takes nil rather than defaulting to `HealthKitService()`: a default
    /// argument is evaluated at the call site, which is not on the main actor,
    /// and the service is.
    init(health: (any HealthDataReading)? = nil, defaults: UserDefaults = .standard) {
        self.health = health ?? HealthKitService()
        self.defaults = defaults
    }

    var isConnected: Bool { repository != nil }

    /// Whether the device has Health at all.
    var isHealthSupported: Bool { health.isSupported }

    /// Whether Apple's sheet has been shown. It cannot say whether the answer
    /// was yes — HealthKit refuses to report that, since saying so would leak
    /// a refusal — so this only distinguishes "never offered" from "asked".
    var hasAskedHealth: Bool { health.hasAsked }

    var isRequestingHealthAccess: Bool { health.isRequestingAuthorization }

    /// Asks for access from a control the user tapped.
    ///
    /// New read types can cause Apple's sheet to appear again; previous
    /// refusals must be changed in Health. Prompt completion is not permission.
    func connectHealth() async {
        guard let repository, let scope, !isLoadingIntegration, !isHealthPausePending else { return }
        let generation = connectionGeneration
        isLoadingIntegration = true
        defer { if generation == connectionGeneration { isLoadingIntegration = false } }
        persistenceError = nil
        do {
            let status = try await repository.integrationStatus()
            guard isCurrent(generation) else { return }
            apply(status)
            guard isIntegrationSupported == true else { throw HealthIntegrationFailure.unsupportedServer }
            guard isHealthSupported else { throw HealthIntegrationFailure.unsupportedDevice }
            guard await health.requestAuthorization() else {
                guard isCurrent(generation) else { return }
                persistenceError = health.errorMessage
                return
            }
            guard isCurrent(generation) else { return }
            let enabled = try await repository.setIntegrationEnabled(true)
            guard isCurrent(generation) else { return }
            apply(enabled)
            guard enabled.enabled else { throw HealthIntegrationFailure.consentRequired }
            defaults.set(true, forKey: scope.preferenceKey)
            await syncFromHealth(generation: generation)
        } catch {
            if isCurrent(generation) { report(error) }
        }
    }

    func requestHealthAccess() async {
        let generation = connectionGeneration
        guard repository != nil else { return }
        guard await health.requestAuthorization() else {
            if isCurrent(generation) { persistenceError = health.errorMessage }
            return
        }
        guard isCurrent(generation), healthSyncEnabled else { return }
        await syncFromHealth(generation: generation)
    }

    /// Stop local uploads immediately, including writes queued by an older
    /// sync. Server disabling is retryable and never silently restored locally.
    func pauseHealthSync() async {
        guard let repository, let scope else { return }
        defaults.set(false, forKey: scope.preferenceKey)
        defaults.set(true, forKey: scope.preferenceKey + ".pendingPause")
        isHealthPausePending = true
        connectionGeneration = UUID()
        let generation = connectionGeneration
        isSyncing = false
        isLoadingIntegration = true
        isLoadingWorkouts = false
        isLoadingGarminWorkouts = false
        isLoading = false
        isSavingGoal = false
        defer { if generation == connectionGeneration { isLoadingIntegration = false } }
        do {
            let status = try await repository.setIntegrationEnabled(false)
            guard isCurrent(generation) else { return }
            apply(status)
            if !status.enabled {
                defaults.removeObject(forKey: scope.preferenceKey + ".pendingPause")
                isHealthPausePending = false
            }
            persistenceError = nil
        } catch {
            if isCurrent(generation) { report(error) }
        }
    }

    /// Today's steps as the server has them, or nil when it has no row for
    /// today. Nil means "not reported", never "zero": a day nobody walked and
    /// a day Health was never asked about are different, and only one of them
    /// is worth drawing as a number.
    var stepsToday: Int? {
        let today = Calendar.current.startOfDay(for: Date())
        return recentDays.first { $0.day == today }?.steps
    }

    /// The last `historyDays` days oldest-first, for a left-to-right strip.
    /// Days the server has nothing for are absent rather than zero.
    var week: [DailyStepCount] {
        recentDays.sorted { $0.day < $1.day }
    }

    /// The largest count in the week, used to scale the bars. Nil when there
    /// is nothing to scale against.
    var weekPeak: Int? { recentDays.map(\.steps).max() }

    /// Averages only reported days. Missing Health data is not treated as zero.
    var weekAverage: Int? {
        guard !recentDays.isEmpty else { return nil }
        return recentDays.reduce(0) { $0 + $1.steps } / recentDays.count
    }

    /// Steps a day the user is aiming for. Eight thousand until the profile
    /// says otherwise, which is the figure the widget showed back when nobody
    /// could change it.
    private(set) var stepGoal: Int = 8_000
    private(set) var isSavingGoal = false

    var goalDaysThisWeek: Int { recentDays.filter { $0.steps >= stepGoal }.count }

    /// Reads the goal off the profile. Quiet on failure: the default is a
    /// usable number, and a banner over the steps card because a target could
    /// not be read would cost more than the target is worth.
    func loadStepGoal() async {
        guard let repository else { return }
        let generation = connectionGeneration
        guard let loaded = try? await repository.stepGoal() else { return }
        guard connectionGeneration == generation else { return }
        stepGoal = loaded
        celebrationGate.rebase(day: Calendar.current.startOfDay(for: Date()), steps: stepsToday, goal: loaded)
    }

    /// Sets the goal, and says so if the server refuses.
    ///
    /// Not optimistic, unlike the steps themselves: this one is a number the
    /// user typed on purpose, and showing it as saved when it was not is
    /// worse than a moment's wait.
    func updateStepGoal(_ steps: Int) async {
        guard let repository, !isSavingGoal else { return }
        let generation = connectionGeneration
        isSavingGoal = true
        defer { if connectionGeneration == generation { isSavingGoal = false } }

        do {
            let saved = try await repository.setStepGoal(steps)
            guard connectionGeneration == generation else { return }
            stepGoal = saved
            celebrationGate.rebase(day: Calendar.current.startOfDay(for: Date()), steps: stepsToday, goal: saved)
            persistenceError = nil
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.userFacingMessage
        }
    }

    /// Direction of the latest reported day compared with the previous one.
    var latestDayChange: Int? {
        let ordered = recentDays.sorted { $0.day < $1.day }
        guard ordered.count >= 2 else { return nil }
        return ordered[ordered.count - 1].steps - ordered[ordered.count - 2].steps
    }

    // MARK: - Connection

    func connect(configuration: APIConfiguration, token: String, accountID: Int) async {
        disconnect()
        celebrationGate = StepGoalCelebrationGate()
        let generation = UUID()
        connectionGeneration = generation
        scope = HealthIntegrationScope(accountID: accountID, serverURL: configuration.serverURL)
        if let scope {
            lastSyncedAt = defaults.object(forKey: scope.preferenceKey + ".lastSync") as? Date
            isHealthPausePending = defaults.bool(forKey: scope.preferenceKey + ".pendingPause")
        }

        do {
            repository = try ActivityAPIRepository(
                configuration: configuration,
                token: token
            )
        } catch {
            repository = nil
            recentDays = []
            persistenceError = error.userFacingMessage
            return
        }

        _ = await reload(generation: generation, showsLoadingState: true)
        guard connectionGeneration == generation, !Task.isCancelled else { return }
        await loadStepGoal()
        guard connectionGeneration == generation, !Task.isCancelled else { return }

        await loadIntegrationStatus()
        guard isCurrent(generation), healthSyncEnabled else { return }
        await syncFromHealth(generation: generation)
    }

    func disconnect() {
        celebrationGate = StepGoalCelebrationGate()
        connectionGeneration = UUID()
        repository = nil
        scope = nil
        // One user's steps must never be shown to the next.
        recentDays = []
        lastImport = nil
        lastSyncedAt = nil
        persistenceError = nil
        isLoading = false
        isSyncing = false
        // Back to the default, so one account's target is never the number
        // the next account is measured against.
        stepGoal = 8_000
        isSavingGoal = false
        serverHealthSyncEnabled = false
        isHealthPausePending = false
        isIntegrationSupported = nil
        isLoadingIntegration = false
        wearableWorkouts = []
        garminWorkouts = []
        nextGarminPage = nil
        visitedGarminPages = []
        hasLoadedGarmin = false
        isLoadingGarminWorkouts = false
        nextWorkoutPage = nil
        visitedWorkoutPages = []
        isLoadingWorkouts = false
        lastSyncAttemptAt = nil
    }

    // MARK: - Health

    /// Reads Health, sends what it reported, and shows what came back.
    func refresh() async {
        let generation = connectionGeneration
        guard !isSyncing else { return }
        guard await readIntegrationStatus(generation: generation) else { return }
        guard isCurrent(generation) else { return }
        guard healthSyncEnabled else {
            _ = await reload(generation: generation, showsLoadingState: false)
            await loadWorkouts(firstPage: true)
            return
        }
        await syncFromHealth(generation: generation)
    }

    /// Foreground refreshes are bounded even during outages. An explicit Retry
    /// remains available immediately; every data write still checks consent.
    func refreshIfNeeded() async {
        guard repository != nil, !isSyncing, !isLoadingIntegration else { return }
        let now = Date()
        guard lastSyncAttemptAt.map({ now.timeIntervalSince($0) >= 300 }) ?? true else { return }
        lastSyncAttemptAt = now
        await refresh()
    }

    func loadIntegrationStatus() async {
        let generation = connectionGeneration
        guard await readIntegrationStatus(generation: generation), isCurrent(generation) else { return }
        await loadWorkouts(firstPage: true)
    }

    func loadMoreWorkouts() async { await loadWorkouts(firstPage: false) }
    func loadGarminWorkouts() async { await loadWorkouts(firstPage: true, garminOnly: true) }
    func loadMoreGarminWorkouts() async { await loadWorkouts(firstPage: false, garminOnly: true) }

    private func readIntegrationStatus(generation: UUID) async -> Bool {
        guard let repository, !isLoadingIntegration else { return false }
        isLoadingIntegration = true
        defer { if generation == connectionGeneration { isLoadingIntegration = false } }
        do {
            let status: HealthIntegrationStatus
            if isHealthPausePending {
                // Reconcile a pause that failed offline before allowing any
                // new upload or showing Enable again on this account/device.
                status = try await repository.setIntegrationEnabled(false)
            } else {
                status = try await repository.integrationStatus()
            }
            guard isCurrent(generation) else { return false }
            apply(status)
            if isHealthPausePending, !status.enabled, let scope {
                defaults.removeObject(forKey: scope.preferenceKey + ".pendingPause")
                isHealthPausePending = false
            }
            guard isIntegrationSupported == true else { throw HealthIntegrationFailure.unsupportedServer }
            persistenceError = nil
            return true
        } catch {
            if isCurrent(generation) { report(error) }
            return false
        }
    }

    func deleteHealthConnectionPreferences(accountID: Int, origin: String) {
        guard let url = URL(string: origin) else { return }
        let deletedScope = HealthIntegrationScope(accountID: accountID, serverURL: url)
        for suffix in ["", ".lastSync", ".pendingPause"] {
            defaults.removeObject(forKey: deletedScope.preferenceKey + suffix)
        }
        if scope == deletedScope { disconnect() }
    }

    private func apply(_ status: HealthIntegrationStatus) {
        serverHealthSyncEnabled = status.enabled && status.consentVersion == HealthSyncPolicy.consentVersion
        isIntegrationSupported = status.schemaVersion == 1
    }

    @discardableResult
    private func loadWorkouts(firstPage: Bool, garminOnly: Bool = false) async -> Bool {
        guard let repository, isIntegrationSupported == true,
              !(garminOnly ? isLoadingGarminWorkouts : isLoadingWorkouts) else { return false }
        let nextPage = garminOnly ? nextGarminPage : nextWorkoutPage
        if !firstPage && nextPage == nil { return true }
        let generation = connectionGeneration
        let page = firstPage ? nil : nextPage
        if garminOnly { isLoadingGarminWorkouts = true } else { isLoadingWorkouts = true }
        defer {
            if generation == connectionGeneration {
                if garminOnly { isLoadingGarminWorkouts = false } else { isLoadingWorkouts = false }
            }
        }
        do {
            let response = try await repository.workoutSummaries(page: page, garminOnly: garminOnly)
            guard isCurrent(generation) else { return false }
            var visited = firstPage ? Set<Int>() : (garminOnly ? visitedGarminPages : visitedWorkoutPages)
            visited.insert(page ?? 1)
            if let next = response.nextPage, visited.contains(next) {
                throw HealthIntegrationFailure.malformedPage
            }
            var rows = firstPage ? [] : (garminOnly ? garminWorkouts : wearableWorkouts)
            for row in response.workouts {
                if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index] = row }
                else { rows.append(row) }
            }
            if garminOnly {
                garminWorkouts = rows
                visitedGarminPages = visited
                nextGarminPage = response.nextPage
                hasLoadedGarmin = true
            } else {
                wearableWorkouts = rows
                visitedWorkoutPages = visited
                nextWorkoutPage = response.nextPage
            }
            return true
        } catch {
            if isCurrent(generation) { report(error) }
            return false
        }
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        generation == connectionGeneration && !Task.isCancelled
    }

    private func requireUploadPermission(_ generation: UUID) throws {
        guard HealthSyncPolicy.canUpload(generation: generation, currentGeneration: connectionGeneration,
                                         serverEnabled: serverHealthSyncEnabled,
                                         deviceEnabled: scope.map { defaults.bool(forKey: $0.preferenceKey) } ?? false,
                                         schemaSupported: isIntegrationSupported == true,
                                         cancelled: Task.isCancelled) else { throw CancellationError() }
    }

    private func report(_ error: any Error) {
        guard !error.isCancellation else { return }
        if let failure = error as? HealthIntegrationFailure {
            switch failure {
            case .unsupportedServer:
                isIntegrationSupported = false
                persistenceError = String(localized: "This testing backend does not support connected workouts yet.", bundle: .app, locale: .app)
            case .consentRequired:
                serverHealthSyncEnabled = false
                persistenceError = String(localized: "Reconnect Apple Health to allow syncing.", bundle: .app, locale: .app)
            case .unsupportedDevice:
                persistenceError = String(localized: "Apple Health is unavailable on this device.", bundle: .app, locale: .app)
            case .malformedPage:
                persistenceError = String(localized: "We couldn't finish reading your activity. Try syncing again.", bundle: .app, locale: .app)
            }
        } else {
            persistenceError = error.userFacingMessage
        }
    }

    private func syncFromHealth(generation: UUID) async {
        guard let repository, isSyncing == false, isCurrent(generation), healthSyncEnabled else { return }
        lastSyncAttemptAt = Date()
        isSyncing = true
        defer { if generation == connectionGeneration { isSyncing = false } }

        let start = Calendar.current.date(
            byAdding: .day,
            value: -(Self.historyDays - 1),
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()

        let importStart = Calendar.current.date(
            byAdding: .day,
            value: -(Self.importHorizonDays - 1),
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        do {
            try requireUploadPermission(generation)
            let steps = try await health.dailySteps(since: start)
            try requireUploadPermission(generation)
            try await repository.record(steps)
            let until = Date()
            var cursor: Data?
            var visitedCursors: Set<Data> = []
            var summary = HealthImportSummary.nothing
            repeat {
                try requireUploadPermission(generation)
                let page = try await health.workoutPage(since: importStart, until: until, cursor: cursor)
                if let next = page.nextCursor, !visitedCursors.insert(next).inserted {
                    throw HealthIntegrationFailure.malformedPage
                }
                for batch in HealthSyncPolicy.batches(page.workouts) {
                    try requireUploadPermission(generation)
                    summary = summary.adding(try await repository.importWorkouts(batch))
                }
                cursor = page.nextCursor
            } while cursor != nil
            try requireUploadPermission(generation)
            guard await reload(generation: generation, showsLoadingState: false) else { return }
            guard await loadWorkouts(firstPage: true) else { return }
            if hasLoadedGarmin {
                guard await loadWorkouts(firstPage: true, garminOnly: true) else { return }
            }
            try requireUploadPermission(generation)
            lastImport = summary
            lastSyncedAt = Date()
            if let scope { defaults.set(lastSyncedAt, forKey: scope.preferenceKey + ".lastSync") }
            persistenceError = nil
            // New imports, linked measurements and corrections all change
            // workout presentation. One reload includes every batch.
            if summary.imported + summary.updated + summary.linked > 0 {
                await onWorkoutsChanged?()
            }
        } catch {
            if isCurrent(generation) { report(error) }
        }
    }

    private func reload(generation: UUID, showsLoadingState: Bool) async -> Bool {
        guard let repository else { return false }
        if showsLoadingState { isLoading = true }
        defer {
            if generation == connectionGeneration, showsLoadingState {
                isLoading = false
            }
        }

        let start = Calendar.current.date(
            byAdding: .day,
            value: -(Self.historyDays - 1),
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()

        do {
            let days = try await repository.steps(since: start)
            guard isCurrent(generation) else { return false }
            recentDays = days
            if celebrationGate.observe(day: Calendar.current.startOfDay(for: Date()), steps: stepsToday, goal: stepGoal) {
                RepbaseCelebrations.show(.stepGoal)
            }
            persistenceError = nil
            return true
        } catch {
            guard isCurrent(generation) else { return false }
            persistenceError = error.userFacingMessage
            return false
        }
    }
}

#if DEBUG
extension ActivityStore {
    /// A week of steps, for looking at the widget without Health data.
    ///
    /// The simulator has no Apple Watch and cannot be tapped from a script, so
    /// the only other way to see this state is to type seven days into the
    /// simulator's Health app by hand. The planner previews exist for the same
    /// reason.
    static var preview: ActivityStore {
        let store = ActivityStore(health: HealthKitService.previewAlreadyAsked())
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Six of seven days, deliberately: a gap is the normal case, and the
        // strip has to look right when one column has nothing behind it.
        let counts: [Int?] = [7642, 4380, 9125, nil, 6033, 11480, 8214]
        store.recentDays = counts.enumerated().compactMap { offset, steps in
            guard let steps,
                  let day = calendar.date(byAdding: .day, value: -offset, to: today)
            else { return nil }
            return DailyStepCount(day: day, steps: steps)
        }
        store.lastImport = HealthImportSummary(
            imported: 2,
            skippedOverlapping: 1,
            alreadyImported: 4
        )
        return store
    }
}
#endif
