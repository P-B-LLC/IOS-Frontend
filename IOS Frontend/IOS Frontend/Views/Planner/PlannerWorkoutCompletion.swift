//
//  PlannerWorkoutCompletion.swift
//  IOS Frontend
//
//  Ticking a planned workout off, and unticking it, and what neither does.
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
//  Unticking a workout that *was* trained has the same shape and the opposite
//  cause. The checkbox owns the plan; the session owns the training, and no
//  amount of unticking removes it. Left silent, the calendar reads "not done"
//  while Training still shows the session, its sets and its volume — the two
//  screens disagreeing, which is the thing this file exists to prevent. So it
//  says what the tick can and cannot reach, and names Undo, which is the one
//  control that removes the training itself.
//

import SwiftUI

enum PlannerWorkoutCompletion {
    /// Whether this tap should say something before it changes the tick.
    ///
    /// Exactly when the tick and the training disagree, in either direction:
    ///
    /// - ticking a workout with no session behind it, which marks the plan
    ///   done while the training counts for nothing; and
    /// - unticking one that *was* trained, where the checkbox cannot take the
    ///   session back and pretending otherwise leaves the calendar saying one
    ///   thing and Training another.
    ///
    /// When they agree there is nothing to say, and a question with an obvious
    /// answer is just an obstacle. Ordinary tasks never ask.
    static func needsConfirmation(
        _ entry: PlannerEntry,
        workouts: WorkoutStore
    ) -> Bool {
        guard entry.isCompletable, entry.category == .workout else { return false }
        let trained = isAlreadyTrained(entry, workouts: workouts)
        return entry.isComplete ? trained : !trained
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
        onProceedAnyway: @escaping (PlannerEntry) -> Void
    ) -> some View {
        confirmationDialog(
            entry.wrappedValue?.isComplete == true
                ? "This workout was trained"
                : "Did you train?",
            isPresented: Binding(
                get: { entry.wrappedValue != nil },
                set: { if !$0 { entry.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: entry.wrappedValue
        ) { pending in
            if let day = openableDay(pending) {
                // The same destination either way, under the name of what it
                // is for here: finishing the workout, or undoing it.
                Button(pending.isComplete ? "Undo in Training" : "Open the workout") {
                    onOpen(day)
                }
            }
            Button(pending.isComplete ? "Untick anyway" : "Just tick it off") {
                onProceedAnyway(pending)
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(message(for: pending, canOpen: openableDay(pending) != nil))
        }
    }

    private func message(for entry: PlannerEntry, canOpen: Bool) -> String {
        guard !entry.isComplete else { return untickMessage(canOpen: canOpen) }
        let base = "Ticking this off marks the plan done, but records no "
            + "session — no sets or distance are saved, and it will not count "
            + "towards your streak or your weekly goal."
        guard canOpen else { return base }
        return base + " Open the workout to finish it properly."
    }

    /// What unticking a trained workout does, and does not do.
    ///
    /// The checkbox owns the plan, not the training. Clearing it here leaves
    /// the session, its sets and everything counted from them exactly where
    /// they are -- so the calendar would say the day was not trained while
    /// Training still says it was. Undo is the one thing that removes the
    /// session, which is why it is offered first and named.
    private func untickMessage(canOpen: Bool) -> String {
        let base = "A session was recorded for this day. Unticking it here "
            + "clears the plan only — the session, its sets and everything "
            + "counted from them stay."
        guard canOpen else { return base }
        return base + " To remove the training itself, use Undo in Training."
    }
}
