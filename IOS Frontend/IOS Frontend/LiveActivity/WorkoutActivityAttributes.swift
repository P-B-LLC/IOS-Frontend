//
//  WorkoutActivityAttributes.swift
//  IOS Frontend
//
//  What the Lock Screen and Dynamic Island show of a lifting session.
//
//  Compiled into both the app, which starts and updates the activity, and the
//  widget extension, which draws it. Keep it free of anything only the app has.
//

import ActivityKit
import Foundation

nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    /// Everything that changes during the session.
    ///
    /// Text arrives already written, in the language chosen inside Rytivo.
    /// The extension cannot know that choice -- it follows the phone's
    /// language -- so it draws what it is given rather than translating
    /// anything itself. Countdowns are dates, not numbers: the system counts
    /// them down on the Lock Screen while the app is not running at all.
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case lifting
            case resting
            case paused
            case done
        }

        var phase: Phase
        var sessionID: Int

        var exerciseName: String
        /// "Exercise 2 of 6"
        var exercisePosition: String
        /// "Set 2 of 4", or "Warm-up · Set 1 of 4"
        var setTitle: String
        /// "W", "D" or "F" for a set that is not a normal one.
        var setBadge: String?
        /// "60 kg × 8": what this set is aiming at.
        var targetText: String?
        /// "Last time 57.5 kg × 8"
        var previousText: String?
        /// "Next: Incline press"
        var nextText: String?

        var loggedSets: Int
        var totalSets: Int
        /// "12 of 20 sets"
        var progressText: String

        var restEndsAt: Date?
        var restStartedAt: Date?
        /// Set while the rest is paused, with what was left.
        var restPausedRemaining: TimeInterval?
        var restTotalSeconds: TimeInterval?

        /// Identify the set and rest the buttons act on, so a tap drawn for
        /// one cannot act on another that has since become current.
        var exerciseID: String?
        var setID: String?
        var restID: String?
        /// Whether the Complete button can log the set as shown.
        var canCompleteSet: Bool

        var labels: Labels
    }

    nonisolated struct Labels: Codable, Hashable, Sendable {
        var rest: String
        var restPaused: String
        var restOver: String
        var completeSet: String
        var pause: String
        var resume: String
        var skip: String
        var addTime: String
        var workoutDone: String
        var openToContinue: String
        /// "Ends at", over the rest's end time on a dimmed Lock Screen.
        /// Optional so an activity started by an earlier build still decodes.
        var restEndsAt: String?
    }

    var workoutName: String
    var startedAt: Date
}

extension WorkoutActivityAttributes.ContentState {
    /// The paused countdown's frozen value, for a `Text(timerInterval:)` that
    /// must stop rather than run: the range ends this far after "now".
    var pausedRange: ClosedRange<Date>? {
        guard let left = restPausedRemaining else { return nil }
        let now = Date()
        return now...now.addingTimeInterval(left)
    }

    var restRange: ClosedRange<Date>? {
        guard let start = restStartedAt, let end = restEndsAt, end > start else { return nil }
        return start...end
    }
}
