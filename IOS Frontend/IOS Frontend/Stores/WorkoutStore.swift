//
//  WorkoutStore.swift
//  IOS Frontend
//
//  Single source of truth for the weekly workout schedule.
//

import Foundation
import Observation

/// The app-facing workout state.
///
/// Each scheduled workout belongs to one day. Views use this store without
/// knowing whether the schedule comes from temporary memory or a local
/// database. Production starts empty until a real `WorkoutPersistence`
/// implementation is injected.
@Observable
final class WorkoutStore {
    private let persistence: any WorkoutPersistence

    /// The workout configured for each weekday. A missing day is unconfigured.
    private(set) var schedule: [Weekday: Workout]
    /// A database adapter can surface load/save failures here later.
    private(set) var persistenceError: String?
    /// Prevents a failed load from being overwritten by an empty snapshot.
    private var didLoadSnapshot: Bool
    /// Remains true when an optimistic change has not reached persistence yet.
    private(set) var hasUnsavedChanges: Bool

    init(persistence: any WorkoutPersistence = EphemeralWorkoutPersistence()) {
        self.persistence = persistence

        do {
            schedule = try persistence.load().schedule
            persistenceError = nil
            didLoadSnapshot = true
            hasUnsavedChanges = false
        } catch {
            schedule = [:]
            persistenceError = "Workout data could not be loaded: \(error.localizedDescription)"
            didLoadSnapshot = false
            hasUnsavedChanges = false
        }
    }

    // MARK: - Lookups

    func workout(on day: Weekday) -> Workout? {
        schedule[day]
    }

    /// Today's weekday, derived from the user's current calendar.
    var today: Weekday? {
        Weekday(calendarWeekday: Calendar.current.component(.weekday, from: Date()))
    }

    /// Editing stays disabled if the initial database load fails.
    var isEditingEnabled: Bool { didLoadSnapshot }

    // MARK: - Day management

    /// Creates or replaces the workout for one day and persists the schedule.
    func saveWorkout(_ workout: Workout, on day: Weekday) {
        guard didLoadSnapshot else { return }
        schedule[day] = workout
        hasUnsavedChanges = true
        persist()
    }

    /// Clears the workout from one day without affecting any other day.
    func removeWorkout(on day: Weekday) {
        guard didLoadSnapshot else { return }
        guard schedule.removeValue(forKey: day) != nil else { return }
        hasUnsavedChanges = true
        persist()
    }

    /// Retries either the failed initial load or the most recent failed save.
    func retryPersistence() {
        if didLoadSnapshot {
            guard hasUnsavedChanges else { return }
            persist()
        } else {
            reloadSnapshot()
        }
    }

    private func reloadSnapshot() {
        do {
            schedule = try persistence.load().schedule
            persistenceError = nil
            didLoadSnapshot = true
            hasUnsavedChanges = false
        } catch {
            persistenceError = "Workout data could not be loaded: \(error.localizedDescription)"
        }
    }

    private func persist() {
        // If loading failed, keep the in-session state visible but never write
        // an empty-derived snapshot over data that may still exist on disk.
        guard didLoadSnapshot else { return }

        do {
            try persistence.save(WorkoutSnapshot(schedule: schedule))
            persistenceError = nil
            hasUnsavedChanges = false
        } catch {
            persistenceError = "Workout changes could not be saved: \(error.localizedDescription)"
            hasUnsavedChanges = true
        }
    }
}

// MARK: - Preview fixtures

extension WorkoutStore {
    /// Samples are opt-in for SwiftUI previews only; production never seeds them.
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

    static let previewSnapshot: WorkoutSnapshot = {
        let workouts = previewWorkouts
        return WorkoutSnapshot(
            schedule: [
                .monday: workouts[0],
                .tuesday: workouts[1],
                .thursday: workouts[2],
                .friday: workouts[3]
            ]
        )
    }()

    static var preview: WorkoutStore {
        WorkoutStore(
            persistence: EphemeralWorkoutPersistence(initialSnapshot: previewSnapshot)
        )
    }
}
