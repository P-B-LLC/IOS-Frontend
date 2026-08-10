//
//  WorkoutStore.swift
//  IOS Frontend
//
//  Single source of truth for the user's workout library and weekly schedule.
//

import Foundation
import Observation

/// The single source of truth for the user's workouts and weekly schedule.
///
/// - `workouts` is the library of workouts the user has built.
/// - `assignments` maps a weekday to a workout **by id**, referencing the
///   library rather than copying workout data — so there is no second source
///   of truth to keep in sync.
///
/// For now everything lives in memory and is seeded with sample data. When
/// persistence (SwiftData) or a backend is added, only this type changes.
@Observable
final class WorkoutStore {
    /// The user's library of workouts.
    private(set) var workouts: [Workout]
    /// Which workout (by id) is scheduled on each weekday.
    private(set) var assignments: [Weekday: Workout.ID]

    init(workouts: [Workout] = WorkoutStore.sampleWorkouts,
         assignments: [Weekday: Workout.ID]? = nil) {
        self.workouts = workouts
        self.assignments = assignments ?? WorkoutStore.sampleAssignments(for: workouts)
    }

    // MARK: - Lookups

    /// The workout with the given id, if it exists in the library.
    func workout(with id: Workout.ID) -> Workout? {
        workouts.first { $0.id == id }
    }

    /// The workout scheduled on `day`, or `nil` if it's a rest day.
    func workout(on day: Weekday) -> Workout? {
        guard let id = assignments[day] else { return nil }
        return workout(with: id)
    }

    /// Today's weekday, derived from the user's current calendar.
    var today: Weekday? {
        Weekday(calendarWeekday: Calendar.current.component(.weekday, from: Date()))
    }

    // MARK: - Scheduling

    /// Assign `workoutID` to `day` (pass `nil` to clear it into a rest day).
    func assign(_ workoutID: Workout.ID?, to day: Weekday) {
        assignments[day] = workoutID
    }

    /// Clear the workout on `day`, making it a rest day.
    func clearAssignment(on day: Weekday) {
        assignments[day] = nil
    }

    // MARK: - Library management

    func addWorkout(_ workout: Workout) {
        workouts.append(workout)
    }

    func updateWorkout(_ workout: Workout) {
        guard let index = workouts.firstIndex(where: { $0.id == workout.id }) else { return }
        workouts[index] = workout
    }

    /// Remove a workout from the library and any day it was assigned to.
    func deleteWorkout(_ workout: Workout) {
        workouts.removeAll { $0.id == workout.id }
        for (day, id) in assignments where id == workout.id {
            assignments[day] = nil
        }
    }
}

extension WorkoutStore {
    /// Sample library used until real persistence exists. The widget and pages
    /// read through the store, so these specific values can be replaced freely.
    static let sampleWorkouts: [Workout] = [
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

    /// Seeds Mon/Tue/Thu/Fri from the sample library, leaving the rest as rest days.
    static func sampleAssignments(for workouts: [Workout]) -> [Weekday: Workout.ID] {
        func id(_ name: String) -> Workout.ID? { workouts.first { $0.name == name }?.id }
        var result: [Weekday: Workout.ID] = [:]
        if let value = id("Upper Body") { result[.monday] = value }
        if let value = id("Lower Body") { result[.tuesday] = value }
        if let value = id("Full Body Conditioning") { result[.thursday] = value }
        if let value = id("Core & Mobility") { result[.friday] = value }
        return result
    }
}
