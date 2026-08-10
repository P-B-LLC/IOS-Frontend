//
//  WorkoutStore.swift
//  IOS Frontend
//
//  Single source of truth for the user's workout scheduling.
//

import Foundation
import Observation

/// The single source of truth for the user's workout scheduling.
///
/// For now the schedule lives in memory and is seeded with placeholder data
/// (see `sampleSchedule`). When real persistence or a backend is added, only
/// this type needs to change — views read the schedule through it, so there is
/// no second source of truth to keep in sync.
@Observable
final class WorkoutStore {
    /// Which workout, if any, is assigned to each day of the week.
    private(set) var schedule: [Weekday: Workout]

    init(schedule: [Weekday: Workout] = WorkoutStore.sampleSchedule) {
        self.schedule = schedule
    }

    /// The workout scheduled for `day`, or `nil` if the day is unscheduled (a rest day).
    func workout(on day: Weekday) -> Workout? {
        schedule[day]
    }

    /// Today's weekday, derived from the user's current calendar.
    var today: Weekday? {
        Weekday(calendarWeekday: Calendar.current.component(.weekday, from: Date()))
    }
}

extension WorkoutStore {
    /// Placeholder schedule used until real workout data exists.
    ///
    /// Deliberately leaves some days empty (rest days) and includes a longer
    /// name so the widget's empty-state and long-name handling are visible.
    /// Replace this with persisted / fetched data later — the widget does not
    /// depend on these specific values.
    static let sampleSchedule: [Weekday: Workout] = [
        .monday: Workout(name: "Upper Body"),
        .tuesday: Workout(name: "Lower Body"),
        .thursday: Workout(name: "Full Body Conditioning"),
        .friday: Workout(name: "Core & Mobility")
        // Wednesday, Saturday, Sunday intentionally omitted (rest days).
    ]
}
