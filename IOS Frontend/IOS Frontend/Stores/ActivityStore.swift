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
    private let health: HealthKitService
    private var connectionGeneration = UUID()

    /// Days the server holds, newest first. The only thing the UI draws.
    private(set) var recentDays: [DailyStepCount] = []
    private(set) var isLoading = false
    private(set) var isSyncing = false
    private(set) var persistenceError: String?
    /// What the last import brought in, or nil before one has run.
    private(set) var lastImport: HealthImportSummary?
    /// When the device last completed a Health-to-server refresh.
    private(set) var lastSyncedAt: Date?

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
    init(health: HealthKitService? = nil) {
        self.health = health ?? HealthKitService()
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
    /// Only useful before the sheet has been shown once; afterwards iOS shows
    /// nothing and the only way back is Settings, which is what the widget
    /// says in that case rather than offering a button that does nothing.
    func connectHealth() async {
        let generation = connectionGeneration
        guard await health.requestAuthorization() else { return }
        await syncFromHealth(generation: generation)
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

    /// Days that met the same 8K target used by the movement rail.
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
            persistenceError = nil
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.localizedDescription
        }
    }

    /// Direction of the latest reported day compared with the previous one.
    var latestDayChange: Int? {
        let ordered = recentDays.sorted { $0.day < $1.day }
        guard ordered.count >= 2 else { return nil }
        return ordered[ordered.count - 1].steps - ordered[ordered.count - 2].steps
    }

    // MARK: - Connection

    func connect(configuration: APIConfiguration, token: String) async {
        let generation = UUID()
        connectionGeneration = generation

        do {
            repository = try ActivityAPIRepository(
                configuration: configuration,
                token: token
            )
        } catch {
            repository = nil
            recentDays = []
            persistenceError = error.localizedDescription
            return
        }

        await reload(generation: generation, showsLoadingState: true)
        await loadStepGoal()

        // Apple's sheet is the whole of the asking. The app requests Health
        // access itself, once, rather than drawing a card that asks the user
        // to ask; a prompt on the screen is a prompt on the screen even when
        // it is polite. HealthKit shows the sheet once per type and silently
        // does nothing on later calls, so a refusal is not nagged at.
        if health.hasAsked == false {
            await health.requestAuthorization()
        }
        await syncFromHealth(generation: generation)
    }

    func disconnect() {
        connectionGeneration = UUID()
        repository = nil
        // One user's steps must never be shown to the next.
        recentDays = []
        lastImport = nil
        lastSyncedAt = nil
        persistenceError = nil
        isLoading = false
        isSyncing = false
    }

    // MARK: - Health

    /// Reads Health, sends what it reported, and shows what came back.
    func refresh() async {
        let generation = connectionGeneration
        guard health.hasAsked else {
            await reload(generation: generation, showsLoadingState: false)
            return
        }
        await syncFromHealth(generation: generation)
    }

    private func syncFromHealth(generation: UUID) async {
        guard let repository, isSyncing == false else { return }
        isSyncing = true
        defer { if generation == connectionGeneration { isSyncing = false } }

        let start = Calendar.current.date(
            byAdding: .day,
            value: -(Self.historyDays - 1),
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()

        let steps = await health.dailySteps(since: start)
        guard generation == connectionGeneration else { return }

        let importStart = Calendar.current.date(
            byAdding: .day,
            value: -(Self.importHorizonDays - 1),
            to: Calendar.current.startOfDay(for: Date())
        ) ?? Date()
        let workouts = await health.workouts(since: importStart)
        guard generation == connectionGeneration else { return }

        do {
            // Nothing to send is not an error. It is what a brand-new
            // simulator, a declined prompt, and a week indoors all look like
            // from here, and `record` and `importWorkouts` both no-op on an
            // empty list rather than making a call that says nothing.
            try await repository.record(steps)
            let summary = try await repository.importWorkouts(workouts)
            guard generation == connectionGeneration else { return }
            // Only replace a summary worth showing with another one. A later
            // refresh that imports nothing must not erase the note saying the
            // last one brought in three runs.
            if summary != .nothing || lastImport == nil {
                lastImport = summary
            }
            await reload(generation: generation, showsLoadingState: false)
            guard generation == connectionGeneration else { return }
            lastSyncedAt = Date()
        } catch {
            guard generation == connectionGeneration else { return }
            persistenceError = error.localizedDescription
        }
    }

    private func reload(generation: UUID, showsLoadingState: Bool) async {
        guard let repository else { return }
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
            guard generation == connectionGeneration else { return }
            recentDays = days
            persistenceError = nil
        } catch {
            guard generation == connectionGeneration else { return }
            persistenceError = error.localizedDescription
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
        let store = ActivityStore(health: .previewAlreadyAsked())
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
