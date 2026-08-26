//
//  PlannerStore.swift
//  IOS Frontend
//
//  Main-actor planner state backed by the generated Repbase API client.
//

import Foundation
import Observation
// For `withAnimation`: retiring a finished overdue task is a timed sequence,
// and the timing belongs beside the state change that drives it.
import SwiftUI

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
    /// Tasks still unfinished from before today, oldest first, reaching back
    /// `pastDueHorizonDays`. Fetched rather than sliced out of the visible
    /// month, so what is overdue does not depend on which month is on screen.
    private(set) var pastDue: [PlannerEntry] = []
    /// Events after today, soonest first, within `upcomingHorizonDays`.
    private(set) var upcomingEvents: [PlannerEntry] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var persistenceError: String?
    private var isSyncingScheduledWorkouts = false

    /// How far ahead "upcoming" looks. Stated rather than assumed, so the list
    /// being short means the diary is empty and not that it was truncated.
    static let upcomingHorizonDays = 60

    /// How far back "past due" looks.
    ///
    /// Unbounded before, on the reasoning that overdue work is unbounded in
    /// time. True, but a task nobody did two months ago is not work any more,
    /// and an unbounded list only grows: it filled the page and buried the
    /// items still worth doing. Anything older stays in the database and on
    /// its own day; it just stops being nagged about.
    static let pastDueHorizonDays = 30

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
        isSyncingScheduledWorkouts = false

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
            persistenceError = error.userFacingMessage
        }
    }

    func disconnect() {
        connectionGeneration = UUID()
        repository = nil
        // One user's plans must never be shown to the next.
        entriesByDate = [:]
        pastDue = []
        upcomingEvents = []
        persistenceError = nil
        isLoading = false
        isSaving = false
        isSyncingScheduledWorkouts = false
        selectedDate = Calendar.current.startOfDay(for: Date())
        visibleMonth = selectedDate
    }

    // MARK: - Reading

    /// The entries on one day, tasks and events together in server order.
    func entries(on date: Date) -> [PlannerEntry] {
        entriesByDate[Self.dateString(date)] ?? []
    }

    /// The day's entries that happen at a stated time, earliest first. These
    /// are the ones a schedule can place.
    func timedEntries(on date: Date) -> [PlannerEntry] {
        entries(on: date)
            .filter { $0.time != nil }
            .sorted { ($0.time ?? "") < ($1.time ?? "") }
    }

    /// The day's entries with no time on them, which belong under the schedule
    /// rather than at some arbitrary hour inside it.
    func untimedEntries(on date: Date) -> [PlannerEntry] {
        entries(on: date).filter { $0.time == nil }
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

    /// Gives every scheduled workout in the current week a planner task, by
    /// asking the server to do it.
    ///
    /// The decision moved to the server, and the reason is the whole point of
    /// this function. Deciding here meant comparing schedules against the
    /// planner and creating whatever was missing, and "missing" covers both a
    /// day never offered and a day whose task the user deleted. The second is
    /// an answer, and re-asking it every launch put deleted tasks back. The
    /// server records having asked, so it can tell them apart.
    func syncScheduledWorkouts(_ workouts: [Workout]) async {
        guard let repository, !isSyncingScheduledWorkouts else { return }
        let dates = workouts.compactMap(\.scheduledDate).sorted()
        guard let first = dates.first, let last = dates.last else { return }

        let generation = connectionGeneration
        isSyncingScheduledWorkouts = true
        defer {
            if connectionGeneration == generation {
                isSyncingScheduledWorkouts = false
            }
        }

        do {
            let created = try await repository.syncScheduledWorkouts(
                from: first,
                to: last
            )
            guard connectionGeneration == generation, !created.isEmpty else { return }
            for entry in created {
                // The month on screen may already hold it, if a refresh landed
                // between the request and its answer.
                let known = entriesByDate[entry.date]?.contains {
                    $0.serverID == entry.serverID
                } ?? false
                if !known {
                    entriesByDate[entry.date, default: []].append(entry)
                }
            }
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = "Scheduled workouts could not be added to the planner: \(error.localizedDescription)"
        }
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
        // Tasks and events draw from different halves of the category list.
        // The server refuses a mismatch, so never send it one.
        if !draft.category.suits(draft.kind) { draft.category = .other }
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
                persistenceError = error.userFacingMessage
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
        withAnimation(.easeOut(duration: 0.25)) {
            apply(to: entry) { $0.isComplete = isComplete }
        }
        persistenceError = nil

        Task {
            do {
                let saved = try await repository.setComplete(entry, isComplete)
                guard connectionGeneration == generation else { return }
                // Under the id it already had. Taking the saved copy's fresh
                // one renamed the row mid-operation, and retirePastDue then
                // looked for an id no longer in the list and gave up — which
                // is why a ticked-off overdue task stayed on screen.
                apply(to: entry) { $0 = saved.identified(as: entry.id) }
                if saved.isComplete {
                    retirePastDue(entry.id, generation: generation)
                }
            } catch {
                guard connectionGeneration == generation else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    apply(to: entry) { $0.isComplete = previous }
                }
                persistenceError = error.userFacingMessage
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
                // Same reasoning as `apply`: the row is held under a different
                // local id in each list, so deleting by that id left a copy
                // behind in whichever list the delete was not made from.
                entriesByDate[entry.date]?.removeAll { $0.isSameEntry(as: entry) }
                pastDue.removeAll { $0.isSameEntry(as: entry) }
                upcomingEvents.removeAll { $0.isSameEntry(as: entry) }
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.userFacingMessage
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
            persistenceError = error.userFacingMessage
        }

        await reloadSurroundings(generation: generation)
    }

    /// What is overdue and what is coming, neither of which lives inside the
    /// month on screen.
    private func reloadSurroundings(generation: UUID) async {
        guard let repository else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let earliest = calendar.date(
                byAdding: .day,
                value: -Self.pastDueHorizonDays,
                to: today
              ),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let horizon = calendar.date(
                byAdding: .day,
                value: Self.upcomingHorizonDays,
                to: today
              )
        else { return }

        do {
            async let overdue = repository.pastDueTasks(
                since: Self.dateString(earliest),
                before: Self.dateString(yesterday)
            )
            async let ahead = repository.upcomingEvents(
                from: Self.dateString(tomorrow),
                to: Self.dateString(horizon)
            )
            let (loadedOverdue, loadedAhead) = try await (overdue, ahead)
            guard connectionGeneration == generation else { return }
            // High first, then oldest first. Something marked high has been
            // waiting *and* matters, and sorting by age alone filed it behind
            // whatever happened to be older.
            pastDue = loadedOverdue.sorted {
                ($0.priority.rank, $0.date) < ($1.priority.rank, $1.date)
            }
            upcomingEvents = loadedAhead.sorted {
                ($0.date, $0.time ?? "") < ($1.date, $1.time ?? "")
            }
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.userFacingMessage
        }
    }

    /// Applies a change wherever the entry is held.
    ///
    /// An overdue task appears in `pastDue` and, if its day happens to fall in
    /// the month on screen, in `entriesByDate` too. Updating only one of them
    /// would leave a task ticked off in one list and outstanding in the other.
    private func apply(to entry: PlannerEntry, _ mutation: (inout PlannerEntry) -> Void) {
        // By server id, not local id: the two lists come from separate reads,
        // so one task is held here as two values with different local ids.
        if let index = entriesByDate[entry.date]?.firstIndex(where: {
            $0.isSameEntry(as: entry)
        }) {
            mutation(&entriesByDate[entry.date]![index])
        }
        if let index = pastDue.firstIndex(where: { $0.isSameEntry(as: entry) }) {
            mutation(&pastDue[index])
        }
        if let index = upcomingEvents.firstIndex(where: { $0.isSameEntry(as: entry) }) {
            mutation(&upcomingEvents[index])
        }
    }

    /// Takes a finished task off the overdue list, but not instantly.
    ///
    /// Overdue means outstanding, so a task that has been done does not belong
    /// there. Removing it the moment it is ticked makes the row vanish before
    /// the line has finished being drawn through it, which reads as the tap
    /// having deleted something. It leaves once the strikethrough has landed.
    private func retirePastDue(_ id: PlannerEntry.ID, generation: UUID) {
        guard pastDue.contains(where: { $0.id == id }) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard connectionGeneration == generation else { return }
            // It may have been unticked while the strikethrough was still on
            // screen, in which case it is outstanding again and stays.
            guard pastDue.first(where: { $0.id == id })?.isComplete == true else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                pastDue.removeAll { $0.id == id }
            }
        }
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
                category: .meeting, date: day(0), time: "10:00:00"
            ),
            PlannerEntry(
                serverID: 10, kind: .event, title: "Sophie's birthday",
                category: .birthday, date: day(0)
            ),
            PlannerEntry(
                serverID: 3, kind: .task, title: "Push Day",
                category: .workout, date: day(0), time: "17:30:00",
                workoutID: 9, workoutName: "Push Day"
            ),
            PlannerEntry(
                serverID: 4, kind: .task,
                title: "Read a chapter of the statistics book",
                category: .study, priority: .low, date: day(0), time: "21:00:00"
            ),
            PlannerEntry(
                serverID: 5, kind: .task, title: "Groceries",
                category: .errand, priority: .high, date: day(0)
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
                category: .appointment, date: day(2), time: "08:15:00"
            ),
            PlannerEntry(
                serverID: 9, kind: .task, title: "Change the bed",
                category: .home, date: day(4)
            ),
            PlannerEntry(
                serverID: 11, kind: .event, title: "Bank holiday",
                category: .holiday, date: day(5)
            ),
            PlannerEntry(
                serverID: 12, kind: .event, title: "Flight to Lisbon",
                category: .travel, date: day(6), time: "06:40:00"
            ),
        ]
        // Sorted the way the server sorts, so a preview cannot show an order
        // the real thing would never produce: priority, then untimed before
        // timed, then the clock.
        store.entriesByDate = Dictionary(grouping: samples, by: \.date)
            .mapValues { day in
                day.sorted { ($0.priority.rank, $0.time ?? "") < ($1.priority.rank, $1.time ?? "") }
            }
        store.pastDue = [
            PlannerEntry(
                serverID: 21, kind: .task, title: "Book the physio",
                category: .health, priority: .high, date: day(-2), time: "09:00:00"
            ),
            PlannerEntry(
                serverID: 20, kind: .task, title: "Renew gym membership",
                category: .errand, date: day(-9)
            ),
        ]
        store.upcomingEvents = [
            PlannerEntry(
                serverID: 30, kind: .event, title: "Dentist",
                category: .appointment, date: day(2), time: "08:15:00"
            ),
            PlannerEntry(
                serverID: 31, kind: .event, title: "Bank holiday",
                category: .holiday, date: day(5)
            ),
            PlannerEntry(
                serverID: 32, kind: .event, title: "Flight to Lisbon",
                category: .travel, date: day(6), time: "06:40:00"
            ),
        ]
        return store
    }
}
