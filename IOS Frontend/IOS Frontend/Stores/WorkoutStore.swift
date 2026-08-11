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

    /// Current-week projection of concrete API WorkoutSchedule records.
    private(set) var schedule: [Weekday: Workout]
    private(set) var persistenceError: String?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var activeSession: ActiveWorkoutSession?
    private(set) var completedSessions: [CompletedWorkoutSession] = []
    private(set) var pendingSetIDs: Set<WorkoutSetDraft.ID> = []

    init(initialSchedule: [Weekday: Workout] = [:]) {
        schedule = initialSchedule
    }

    // MARK: - Connection

    func connect(configuration: APIConfiguration, token: String) async {
        let generation = UUID()
        connectionGeneration = generation
        activeSession = nil
        pendingSetIDs = []

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
    }

    // MARK: - Lookups

    func workout(on day: Weekday) -> Workout? {
        schedule[day]
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

    var hasPendingSetChanges: Bool {
        !pendingSetIDs.isEmpty
    }

    func isSetPending(_ id: WorkoutSetDraft.ID) -> Bool {
        pendingSetIDs.contains(id)
    }

    // MARK: - Day management

    func saveWorkout(_ workout: Workout, on day: Weekday) {
        guard let repository, !isSaving else { return }
        let generation = connectionGeneration
        let existing = schedule[day]
        let date = dateString(for: day)
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
            guard connectionGeneration == generation else { return }
            isSaving = false
        }
    }

    func removeWorkout(on day: Weekday) {
        guard let repository,
              let workout = schedule[day],
              !isSaving else {
            return
        }
        let generation = connectionGeneration
        isSaving = true
        persistenceError = nil

        Task {
            do {
                try await repository.removeSchedule(workout)
                guard connectionGeneration == generation else { return }
                schedule.removeValue(forKey: day)
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.localizedDescription
            }
            guard connectionGeneration == generation else { return }
            isSaving = false
        }
    }

    // MARK: - Session logging

    func startSession(on day: Weekday) {
        guard let repository,
              activeSession == nil,
              let workout = schedule[day],
              !workout.exercises.isEmpty,
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
            } catch {
                guard connectionGeneration == generation else { return }
                persistenceError = error.localizedDescription
            }
            guard connectionGeneration == generation else { return }
            isSaving = false
        }
    }

    func updateSessionSet(
        on day: Weekday,
        exerciseID: Exercise.ID,
        setID: WorkoutSetDraft.ID,
        weightKilograms: String? = nil,
        reps: String? = nil
    ) {
        mutateSet(on: day, exerciseID: exerciseID, setID: setID) { set in
            if let weightKilograms {
                set.weightKilograms = weightKilograms
            }
            if let reps {
                set.reps = reps
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
              let exercise = sessionExercise(on: day, id: exerciseID),
              let set = exercise.sets.first(where: { $0.id == setID }) else {
            return
        }

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
                        sessionExerciseID: exercise.sessionExerciseID
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
            try await repository.endSession(id: session.serverID)
            completedSessions.append(
                CompletedWorkoutSession(session: session, endedAt: Date())
            )
            activeSession = nil
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
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    // MARK: - Retry and mapping

    func retryPersistence() {
        guard let repository, !isLoading, !isSaving else { return }
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
        persistenceError = nil
        do {
            let loaded = try await repository.loadWeek(
                dateByDay: dateStringsForCurrentWeek()
            )
            guard connectionGeneration == generation else { return }
            schedule = loaded
        } catch {
            guard connectionGeneration == generation else { return }
            persistenceError = error.localizedDescription
        }
        if showsLoadingState, connectionGeneration == generation {
            isLoading = false
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
        let start = calendar.startOfDay(for: referenceDate)
        let calendarWeekday = calendar.component(.weekday, from: start)
        let daysSinceMonday = (calendarWeekday + 5) % 7
        let monday = calendar.date(
            byAdding: .day,
            value: -daysSinceMonday,
            to: start
        ) ?? start
        let date = calendar.date(
            byAdding: .day,
            value: day.rawValue - 1,
            to: monday
        ) ?? monday
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
                .monday: workouts[0],
                .tuesday: workouts[1],
                .thursday: workouts[2],
                .friday: workouts[3]
            ]
        )
    }
}
