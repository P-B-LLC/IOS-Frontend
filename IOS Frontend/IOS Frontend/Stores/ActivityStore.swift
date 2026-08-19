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
    /// What can be shown, and why not when nothing can.
    enum Availability: Equatable {
        /// A device with no Health at all.
        case unsupported
        /// Health exists and the user has never been asked.
        case notConnected
        /// The user has been asked. Whether they agreed is not knowable:
        /// HealthKit refuses to distinguish a refusal from an empty Health
        /// app, because saying which would itself be health information.
        case connected
    }

    private var repository: ActivityAPIRepository?
    private let health: HealthKitService
    private var connectionGeneration = UUID()

    /// Days the server holds, newest first. The only thing the UI draws.
    private(set) var recentDays: [DailyStepCount] = []
    private(set) var isLoading = false
    private(set) var isSyncing = false
    private(set) var persistenceError: String?

    /// How far back the widget reads and sends.
    ///
    /// A week, because that is what the strip shows. Health keeps far more,
    /// but importing all of it on every launch would send thousands of days
    /// nobody is looking at.
    static let historyDays = 7

    init(health: HealthKitService = HealthKitService()) {
        self.health = health
    }

    var isConnected: Bool { repository != nil }
    var isRequestingHealthAccess: Bool { health.isRequestingAuthorization }
    var healthErrorMessage: String? { health.errorMessage }

    var availability: Availability {
        if health.isSupported == false { return .unsupported }
        return health.hasAsked ? .connected : .notConnected
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

        // Only if the user has already agreed once. Connecting must not make
        // Apple's permission sheet appear on a launch nobody asked it to.
        if health.hasAsked {
            await syncFromHealth(generation: generation)
        }
    }

    func disconnect() {
        connectionGeneration = UUID()
        repository = nil
        // One user's steps must never be shown to the next.
        recentDays = []
        persistenceError = nil
        isLoading = false
        isSyncing = false
    }

    // MARK: - Health

    /// Asks Apple for read access, then brings in what it allows.
    ///
    /// Called from a button, never automatically: the sheet is Apple's, it
    /// appears once, and spending it on a launch the user did not ask for
    /// would leave them no way to say yes later.
    func connectHealth() async {
        let generation = connectionGeneration
        guard await health.requestAuthorization() else { return }
        await syncFromHealth(generation: generation)
    }

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

        let fromHealth = await health.dailySteps(since: start)
        guard generation == connectionGeneration else { return }

        // Nothing to send is not an error. It is what a brand-new simulator,
        // a declined prompt, and a week indoors all look like from here.
        guard fromHealth.isEmpty == false else {
            await reload(generation: generation, showsLoadingState: false)
            return
        }

        do {
            try await repository.record(fromHealth)
            guard generation == connectionGeneration else { return }
            await reload(generation: generation, showsLoadingState: false)
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
        return store
    }
}
#endif
