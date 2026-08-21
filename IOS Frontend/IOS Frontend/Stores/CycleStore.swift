//
//  CycleStore.swift
//  IOS Frontend
//
//  Main-actor rotation state, read from the server.
//
//  Which day of the split it is today is never worked out here. The server
//  states it, because the answer has to be the same on every device the user
//  opens, and an app that is one day out is worse than one that says nothing.
//

import Foundation
import Observation

@Observable
@MainActor
final class CycleStore {
    private var repository: CycleAPIRepository?
    private var connectionGeneration = UUID()

    private(set) var cycles: [WorkoutCycle] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var persistenceError: String?
    /// What the last shift did, for a message the user can read and dismiss.
    var lastShift: CycleShiftOutcome?

    init() {}

    var isConnected: Bool { repository != nil }

    /// The rotation in force, if the user runs one. Weekly plans are the
    /// common case and have no cycle at all.
    var activeCycle: WorkoutCycle? {
        cycles.first { $0.isActive }
    }

    var hasCycle: Bool { activeCycle != nil }

    // MARK: - Connection

    func connect(configuration: APIConfiguration, token: String) async {
        let generation = UUID()
        connectionGeneration = generation

        do {
            repository = try CycleAPIRepository(
                configuration: configuration,
                token: token
            )
        } catch {
            repository = nil
            cycles = []
            persistenceError = error.localizedDescription
            return
        }

        await reload(generation: generation, showsLoadingState: true)
    }

    func disconnect() {
        connectionGeneration = UUID()
        repository = nil
        // One account's plan must never be shown to the next.
        cycles = []
        persistenceError = nil
        lastShift = nil
        isLoading = false
        isSaving = false
    }

    // MARK: - Reading

    func refresh() async {
        await reload(generation: connectionGeneration, showsLoadingState: false)
    }

    private func reload(generation: UUID, showsLoadingState: Bool) async {
        guard let repository else { return }
        if showsLoadingState { isLoading = true }
        defer {
            if connectionGeneration == generation, showsLoadingState {
                isLoading = false
            }
        }

        do {
            let loaded = try await repository.cycles()
            guard connectionGeneration == generation else { return }
            cycles = loaded
            persistenceError = nil
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.localizedDescription
        }
    }

    // MARK: - Writing

    /// Creates the rotation and writes its first several turns to the calendar.
    ///
    /// Planning ahead is part of creating: a rotation that exists but has put
    /// nothing on any day would look, from the training screens, like nothing
    /// had been set up at all.
    func create(_ draft: WorkoutCycleDraft) async {
        await save { repository in
            let created = try await repository.create(draft)
            try await repository.planAhead(
                created,
                through: Self.planningHorizon(from: draft.anchorDate)
            )
        }
    }

    func update(_ cycle: WorkoutCycle) async {
        await save { repository in
            let updated = try await repository.update(cycle)
            try await repository.planAhead(
                updated,
                through: Self.planningHorizon(from: Date())
            )
        }
    }

    /// Stops the rotation. Days already trained keep their record; days it had
    /// written but nothing happened on are the server's to tidy.
    func end(_ cycle: WorkoutCycle) async {
        await save { try await $0.delete(cycle) }
    }

    /// Pushes everything still to come back by a day, after an unplanned rest.
    func restedToday() async {
        guard let cycle = activeCycle else { return }
        await performShift { try await $0.shift(cycle, byDays: 1) }
    }

    /// Re-anchors so whatever is owed happens today, after several days off.
    func resumeToday() async {
        guard let cycle = activeCycle else { return }
        await performShift { try await $0.resumeToday(cycle) }
    }

    /// Kept apart from `save` because a shift has something to report, and the
    /// count of what moved is worth showing rather than swallowing.
    private func performShift(
        _ work: (CycleAPIRepository) async throws -> (WorkoutCycle, CycleShiftOutcome)
    ) async {
        guard let repository, !isSaving else { return }
        let generation = connectionGeneration
        isSaving = true
        defer { if connectionGeneration == generation { isSaving = false } }

        do {
            let (_, outcome) = try await work(repository)
            guard connectionGeneration == generation else { return }
            lastShift = outcome
            await reload(generation: generation, showsLoadingState: false)
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.localizedDescription
        }
    }

    /// Fills the calendar further out, so paging forward finds something.
    func planAhead(through date: Date) async {
        guard let cycle = activeCycle else { return }
        await save { try await $0.planAhead(cycle, through: date) }
    }

    /// Sixteen weeks. Far enough that paging forward finds something, near
    /// enough that a plan abandoned next week has not filled a year.
    private static func planningHorizon(from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 112, to: date) ?? date
    }

    private func save(
        _ work: @escaping (CycleAPIRepository) async throws -> Void
    ) async {
        guard let repository, !isSaving else { return }
        let generation = connectionGeneration
        isSaving = true
        defer { if connectionGeneration == generation { isSaving = false } }

        do {
            try await work(repository)
            guard connectionGeneration == generation else { return }
            // A shift replaces the rotation rather than editing it, so the new
            // one has to be read back rather than patched in place.
            await reload(generation: generation, showsLoadingState: false)
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.localizedDescription
        }
    }
}

#if DEBUG
extension CycleStore {
    /// A push/pull/legs rotation over eight days, for looking at the screens
    /// without an account.
    static var preview: CycleStore {
        let store = CycleStore()
        let today = Calendar.current.startOfDay(for: Date())
        store.cycles = [
            WorkoutCycle(
                id: 1,
                name: "PPL + rest",
                length: 8,
                anchorDate: Calendar.current.date(
                    byAdding: .day, value: -2, to: today
                ) ?? today,
                slots: [
                    WorkoutCycleSlot(serverID: 1, position: 1, workoutID: 11, workoutName: "Push"),
                    WorkoutCycleSlot(serverID: 2, position: 2, workoutID: 12, workoutName: "Pull"),
                    WorkoutCycleSlot(serverID: 3, position: 3, workoutID: 13, workoutName: "Legs"),
                    WorkoutCycleSlot(serverID: 4, position: 4, workoutID: nil, workoutName: nil),
                    WorkoutCycleSlot(serverID: 5, position: 5, workoutID: 11, workoutName: "Push"),
                    WorkoutCycleSlot(serverID: 6, position: 6, workoutID: 12, workoutName: "Pull"),
                    WorkoutCycleSlot(serverID: 7, position: 7, workoutID: 13, workoutName: "Legs"),
                    WorkoutCycleSlot(serverID: 8, position: 8, workoutID: nil, workoutName: nil),
                ],
                endedOn: nil,
                currentPosition: 3,
                currentWorkoutName: "Legs",
                nextWorkoutName: "Push",
                nextWorkoutDate: Calendar.current.date(
                    byAdding: .day, value: 2, to: today
                )
            )
        ]
        return store
    }

    /// An account with no rotation, which is most of them.
    static var previewEmpty: CycleStore { CycleStore() }
}
#endif
