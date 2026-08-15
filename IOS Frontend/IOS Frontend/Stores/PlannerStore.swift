//
//  PlannerStore.swift
//  IOS Frontend
//
//  Main-actor planner state backed by the generated Repbase API client.
//

import Foundation
import Observation

@Observable
@MainActor
final class PlannerStore {
    private var repository: PlannerAPIRepository?
    private var connectionGeneration = UUID()

    /// Everything loaded for the visible month, keyed by its `YYYY-MM-DD` date.
    /// The month is the unit because the calendar has to mark every day in it,
    /// and the day list is a slice of the same data rather than a second fetch.
    private(set) var entriesByDate: [String: [PlannerEntry]] = [:]
    /// The day whose list is shown, and the date a new entry is filled in with.
    private(set) var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    /// Any day inside the month on screen.
    private(set) var visibleMonth: Date = Calendar.current.startOfDay(for: Date())
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var persistenceError: String?

    var isConnected: Bool { repository != nil }

    /// Why editing is off, or nil when it is available. Shown rather than
    /// leaving a dead control with no explanation.
    var editingBlockedReason: String? {
        if repository == nil {
            return "Not connected to Repbase, so tasks cannot be saved yet."
        }
        if isSaving { return "Saving..." }
        return nil
    }

    var isEditingEnabled: Bool { editingBlockedReason == nil }

    init() {}

    // MARK: - Connection

    func connect(configuration: APIConfiguration, token: String) async {
        let generation = UUID()
        connectionGeneration = generation
        isLoading = false
        isSaving = false

        do {
            let repository = try PlannerAPIRepository(
                configuration: configuration,
                token: token
            )
            self.repository = repository
            await reloadMonth(generation: generation, showsLoadingState: true)
        } catch {
            self.repository = nil
            entriesByDate = [:]
            persistenceError = error.localizedDescription
        }
    }

    func disconnect() {
        connectionGeneration = UUID()
        repository = nil
        // One user's plans must never be shown to the next.
        entriesByDate = [:]
        persistenceError = nil
        isLoading = false
        isSaving = false
        selectedDate = Calendar.current.startOfDay(for: Date())
        visibleMonth = selectedDate
    }

    // MARK: - Reading

    /// The entries on one day, tasks and events together in server order.
    func entries(on date: Date) -> [PlannerEntry] {
        entriesByDate[Self.dateString(date)] ?? []
    }

    /// Whether a day has anything on it, which is what the calendar marks.
    func hasEntries(on date: Date) -> Bool {
        !(entriesByDate[Self.dateString(date)] ?? []).isEmpty
    }

    /// The categories present on a day, in a stable order, for the dots under
    /// a calendar cell.
    func categories(on date: Date) -> [PlannerCategory] {
        var seen: Set<PlannerCategory> = []
        return entries(on: date).compactMap { entry in
            seen.insert(entry.category).inserted ? entry.category : nil
        }
    }

    /// How much of a day's tasks are done, 0...1. Events do not count: they are
    /// not something to finish.
    func progress(on date: Date) -> Double {
        let tasks = entries(on: date).filter(\.isCompletable)
        guard !tasks.isEmpty else { return 0 }
        return Double(tasks.filter(\.isComplete).count) / Double(tasks.count)
    }

    func taskCounts(on date: Date) -> (done: Int, total: Int) {
        let tasks = entries(on: date).filter(\.isCompletable)
        return (tasks.filter(\.isComplete).count, tasks.count)
    }

    // MARK: - Navigation

    func select(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        selectedDate = day
        guard !Self.isSameMonth(day, visibleMonth) else { return }
        visibleMonth = day
        Task { await reloadMonth(generation: connectionGeneration, showsLoadingState: false) }
    }

    func showMonth(offsetBy months: Int) {
        let calendar = Calendar.current
        guard let moved = calendar.date(byAdding: .month, value: months, to: visibleMonth)
        else { return }
        visibleMonth = moved
        Task { await reloadMonth(generation: connectionGeneration, showsLoadingState: false) }
    }

    func showToday() {
        let today = Calendar.current.startOfDay(for: Date())
        let wasElsewhere = !Self.isSameMonth(today, visibleMonth)
        selectedDate = today
        visibleMonth = today
        guard wasElsewhere else { return }
        Task { await reloadMonth(generation: connectionGeneration, showsLoadingState: false) }
    }

    // MARK: - Writing

    func save(_ draft: PlannerEntry) {
        guard let repository, !isSaving else { return }
        let generation = connectionGeneration
        var draft = draft
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.title.isEmpty else { return }
        // An event is not something to finish, so it never carries completion.
        if !draft.isCompletable { draft.isComplete = false }
        // Only a workout task points at a workout; changing the category away
        // from workout must not leave the link dangling behind it.
        if draft.category != .workout { draft.workoutID = nil }
        isSaving = true
        persistenceError = nil

        Task {
            do {
                if draft.serverID == nil {
                    try await repository.create(draft)
                } else {
                    try await repository.update(draft)
                }
                await reloadMonth(generation: generation, showsLoadingState: false)
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.localizedDescription
            }
            isSaving = false
        }
    }

    /// Ticks a task off, or puts it back.
    ///
    /// The row flips straight away and is put back if the server refuses, so a
    /// checkbox never sits there unresponsive while a request is in flight.
    func setComplete(_ entry: PlannerEntry, _ isComplete: Bool) {
        guard let repository, entry.isCompletable else { return }
        let generation = connectionGeneration
        let previous = entry.isComplete
        apply(to: entry) { $0.isComplete = isComplete }
        persistenceError = nil

        Task {
            do {
                let saved = try await repository.setComplete(entry, isComplete)
                guard connectionGeneration == generation else { return }
                apply(to: entry) { $0 = saved }
            } catch {
                guard connectionGeneration == generation else { return }
                apply(to: entry) { $0.isComplete = previous }
                persistenceError = error.localizedDescription
            }
        }
    }

    func delete(_ entry: PlannerEntry) {
        guard let repository, !isSaving else { return }
        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil

        Task {
            do {
                try await repository.delete(entry)
                guard connectionGeneration == generation else { return }
                entriesByDate[entry.date]?.removeAll { $0.id == entry.id }
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.localizedDescription
            }
            isSaving = false
        }
    }

    func retry() {
        guard repository != nil, !isLoading else { return }
        Task { await reloadMonth(generation: connectionGeneration, showsLoadingState: true) }
    }

    // MARK: - Loading

    private func reloadMonth(generation: UUID, showsLoadingState: Bool) async {
        guard let repository else { return }
        // The grid shows a few days either side of the month, so the range is
        // padded rather than clipped to the first and last of the month.
        guard let range = Self.monthRange(around: visibleMonth) else { return }
        if showsLoadingState { isLoading = true }
        persistenceError = nil

        defer {
            // Cleared unconditionally: a stale return must not leave the page
            // spinning with nothing on screen explaining it.
            if showsLoadingState { isLoading = false }
        }

        do {
            let loaded = try await repository.entries(from: range.start, to: range.end)
            guard connectionGeneration == generation else { return }
            entriesByDate = Dictionary(grouping: loaded, by: \.date)
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.localizedDescription
        }
    }

    private func apply(to entry: PlannerEntry, _ mutation: (inout PlannerEntry) -> Void) {
        guard let index = entriesByDate[entry.date]?.firstIndex(where: { $0.id == entry.id })
        else { return }
        mutation(&entriesByDate[entry.date]![index])
    }

    // MARK: - Dates

    /// Literal `YYYY-MM-DD`, built from calendar components rather than a
    /// formatter so it cannot drift with the device locale.
    nonisolated static func dateString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    nonisolated static func isSameMonth(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.isDate(lhs, equalTo: rhs, toGranularity: .month)
    }

    /// A fortnight either side of the month, which covers the leading and
    /// trailing days the grid borrows from the neighbouring months.
    private static func monthRange(around date: Date) -> (start: String, end: String)? {
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: date),
              let start = calendar.date(byAdding: .day, value: -14, to: month.start),
              let end = calendar.date(byAdding: .day, value: 14, to: month.end)
        else { return nil }
        return (dateString(start), dateString(end))
    }
}

extension PlannerStore {
    /// Sample days for previews and layout checks.
    ///
    /// Never reached when signed in: the real store starts empty and fills from
    /// the API. Deliberately mixed — done and not, timed and untimed, tasks and
    /// events — so a layout that only survives the easy case shows up.
    static var preview: PlannerStore {
        let store = PlannerStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = { (offset: Int) in
            dateString(calendar.date(byAdding: .day, value: offset, to: today) ?? today)
        }

        let samples: [PlannerEntry] = [
            PlannerEntry(
                serverID: 1, kind: .task, title: "Morning skincare",
                category: .habit, date: day(0), isComplete: true
            ),
            PlannerEntry(
                serverID: 2, kind: .event, title: "Zoom team meeting",
                category: .work, date: day(0), time: "10:00:00"
            ),
            PlannerEntry(
                serverID: 3, kind: .task, title: "Push Day",
                category: .workout, date: day(0), time: "17:30:00",
                workoutID: 9, workoutName: "Push Day"
            ),
            PlannerEntry(
                serverID: 4, kind: .task,
                title: "Read a chapter of the statistics book",
                category: .study, date: day(0), time: "21:00:00"
            ),
            PlannerEntry(
                serverID: 5, kind: .task, title: "Groceries",
                category: .errand, date: day(0)
            ),
            PlannerEntry(
                serverID: 6, kind: .task, title: "Lights out by eleven",
                category: .sleep, date: day(0), time: "23:00:00"
            ),
            PlannerEntry(
                serverID: 7, kind: .task, title: "Leg Day",
                category: .workout, date: day(1), workoutID: 10, workoutName: "Leg Day"
            ),
            PlannerEntry(
                serverID: 8, kind: .event, title: "Dentist",
                category: .health, date: day(2), time: "08:15:00"
            ),
            PlannerEntry(
                serverID: 9, kind: .task, title: "Change the bed",
                category: .home, date: day(4)
            ),
        ]
        store.entriesByDate = Dictionary(grouping: samples, by: \.date)
        return store
    }
}
