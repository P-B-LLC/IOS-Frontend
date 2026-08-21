//
//  PlannerWorkoutCompletion.swift
//  IOS Frontend
//
//  Ticking a planned workout off, and what that does not do.
//
//  A planner tick sets `completed_at` on the task and nothing else. It writes
//  no session, so the workout counts for nothing: no sets, no distance, no
//  route, no miles on the shoes, nothing towards the streak or the weekly
//  goal, and no Completed badge on the training day. The row goes grey and the
//  rest of the app never hears about it.
//
//  So a workout tick asks first, and offers the session instead. Both answers
//  stay available — somebody who ran with a watch and is tidying up the plan
//  afterwards should not be trapped — but the consequence is on screen rather
//  than discovered weeks later when the streak is wrong.
//

import SwiftUI

enum PlannerWorkoutCompletion {
    /// Whether ticking this entry should ask before it marks the plan done.
    ///
    /// Only when the tick is going on, only for a workout, and only when no
    /// session was recorded that day. Unticking, ordinary tasks, and a workout
    /// already trained all go straight through: a question with an obvious
    /// answer is just an obstacle.
    static func needsConfirmation(
        _ entry: PlannerEntry,
        workouts: WorkoutStore
    ) -> Bool {
        guard !entry.isComplete,
              entry.isCompletable,
              entry.category == .workout else { return false }
        return !isAlreadyTrained(entry, workouts: workouts)
    }

    /// Whether a session for this workout was finished on this day.
    static func isAlreadyTrained(
        _ entry: PlannerEntry,
        workouts: WorkoutStore
    ) -> Bool {
        guard let date = day(from: entry.date) else { return false }
        return workouts.isCompleted(workoutName: name(of: entry), on: date)
    }

    /// The day view to offer, or nil when there is none worth offering.
    ///
    /// Only dates in the week the schedule holds. A day view for last Tuesday
    /// would open on an empty page, which is a worse answer than not offering
    /// to open it at all.
    static func openableDay(
        _ entry: PlannerEntry,
        workouts: WorkoutStore
    ) -> Weekday? {
        workouts.weekday(forDateString: entry.date)
    }

    /// The planner titles a workout entry with the workout's name, but the
    /// name is carried separately when the server knows it.
    static func name(of entry: PlannerEntry) -> String {
        entry.workoutName ?? entry.title
    }

    static func day(from value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }
}

extension View {
    /// The question a workout tick asks, wherever it is asked from.
    ///
    /// Held in one place because a planned workout can be ticked off from
    /// three screens, and three copies of this would drift apart.
    func plannerWorkoutCompletionDialog(
        entry: Binding<PlannerEntry?>,
        openableDay: @escaping (PlannerEntry) -> Weekday?,
        onOpen: @escaping (Weekday) -> Void,
        onTickAnyway: @escaping (PlannerEntry) -> Void
    ) -> some View {
        confirmationDialog(
            "Did you train?",
            isPresented: Binding(
                get: { entry.wrappedValue != nil },
                set: { if !$0 { entry.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: entry.wrappedValue
        ) { pending in
            if let day = openableDay(pending) {
                Button("Open the workout") { onOpen(day) }
            }
            Button("Just tick it off") { onTickAnyway(pending) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(message(for: pending, canOpen: openableDay(pending) != nil))
        }
    }

    private func message(for entry: PlannerEntry, canOpen: Bool) -> String {
        let base = "Ticking this off marks the plan done, but records no "
            + "session — no sets or distance are saved, and it will not count "
            + "towards your streak or your weekly goal."
        guard canOpen else { return base }
        return base + " Open the workout to finish it properly."
    }
}
