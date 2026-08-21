//
//  WorkoutCycle.swift
//  IOS Frontend
//
//  A training rotation that repeats every N days rather than every week.
//
//  A weekly plan can be described by a weekday. An eight-day split cannot: it
//  falls on Monday, then Tuesday, then Wednesday, and keeps drifting. What it
//  has instead is a length and an anchor, and every date follows from those.
//

import Foundation

/// One day of a rotation.
nonisolated struct WorkoutCycleSlot: Identifiable, Hashable, Sendable {
    /// The server's id, or nil for a slot being drafted.
    var serverID: Int?
    /// 1 through the cycle's length.
    var position: Int
    /// The workout on this day. Nil is a rest day, which is a slot in its own
    /// right: a six-workout two-rest rotation is eight days, not six.
    var workoutID: Int?
    var workoutName: String?

    var id: Int { position }
    var isRest: Bool { workoutID == nil }

    var displayName: String { workoutName ?? "Rest" }
}

nonisolated struct WorkoutCycle: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    /// Days in one turn, rest days included.
    var length: Int
    /// The date slot 1 falls on. Shifting the plan moves this and nothing else.
    var anchorDate: Date
    var slots: [WorkoutCycleSlot]
    /// Nil while the rotation is the one in force. A closed rule is kept so
    /// weeks already trained still resolve through what was planned then.
    var endedOn: Date?

    // Everything below is the server's arithmetic, not the app's. Two devices
    // disagreeing about which day of the split it is would be worse than not
    // showing it at all.

    /// Where the rotation is today, counting from one.
    let currentPosition: Int
    /// What today is, by the plan. "Rest" on a rest slot.
    let currentWorkoutName: String
    /// The next day that is a workout rather than a rest.
    let nextWorkoutName: String
    let nextWorkoutDate: Date?

    var isActive: Bool { endedOn == nil }

    /// "Day 3 of 8", the thing an eight-day split makes hard to keep track of.
    var positionText: String { "Day \(currentPosition) of \(length)" }

    /// The slots in order, filling any the server has no row for. A rotation
    /// with a gap in its positions is still a rotation of `length` days.
    var orderedSlots: [WorkoutCycleSlot] {
        (1...max(length, 1)).map { position in
            slots.first { $0.position == position }
                ?? WorkoutCycleSlot(position: position, workoutID: nil)
        }
    }
}

/// A rotation being built, before the server has given it an identity.
nonisolated struct WorkoutCycleDraft: Hashable, Sendable {
    var name: String = ""
    var length: Int = 8
    var anchorDate: Date = Calendar.current.startOfDay(for: Date())
    /// One entry per day, rest included. Kept the same size as `length` so a
    /// slot is never silently dropped when the length changes.
    var slots: [WorkoutCycleSlot] = (1...8).map {
        WorkoutCycleSlot(position: $0, workoutID: nil)
    }

    /// Grows or trims the slots to match the length, keeping what was chosen.
    mutating func resize(to newLength: Int) {
        let clamped = max(1, min(newLength, 31))
        length = clamped
        if slots.count < clamped {
            slots.append(
                contentsOf: (slots.count + 1...clamped).map {
                    WorkoutCycleSlot(position: $0, workoutID: nil)
                }
            )
        } else if slots.count > clamped {
            slots = Array(slots.prefix(clamped))
        }
    }

    /// Whether it is worth sending. A rotation of nothing but rest days would
    /// schedule nothing and report no next workout.
    var hasAnyWorkout: Bool { slots.contains { $0.workoutID != nil } }
}

/// What a shift did, counted, so the app can say it rather than guess.
nonisolated struct CycleShiftOutcome: Hashable, Sendable {
    let daysShifted: Int
    /// Future days the rotation had written that were rebuilt.
    let removed: Int
    let scheduled: Int
    /// Future days left alone because something had already happened on them.
    let kept: Int
}
