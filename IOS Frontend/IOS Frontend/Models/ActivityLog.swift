//
//  ActivityLog.swift
//  IOS Frontend
//
//  An activity written down after it happened: a tennis match, a hike, a
//  class. What was asked, what was answered, and what can be sent.
//

import Foundation

/// The answers in the "log an activity" form, before they are sent.
///
/// Text fields stay text until sending so a half-typed value is never
/// rounded or rejected while somebody is still typing it, and the draft can
/// be recovered exactly as it was left. `validated()` is the one place that
/// turns it into numbers, and the only way to get an `ActivityLogEntry`.
nonisolated struct ActivityLogDraft: Hashable, Codable, Sendable {
    var activity: WorkoutActivity
    /// Blank means the activity's own name.
    var name: String = ""
    /// When it finished. Asked rather than the start because people log
    /// straight after, when "now" is right and the start follows from the
    /// duration.
    var endedAt: Date = Date()
    var hours: String = ""
    var minutes: String = ""
    var distance: String = ""
    var distanceUnit: DistanceUnit = .kilometers
    var perceivedEffort: Int?
    var calories: String = ""
    var notes: String = ""
    var details = ActivityDetails()

    static let maximumNotesLength = 2000
    static let durationRange = 60...86_400
    static let caloriesRange = 1...20_000

    nonisolated enum DistanceUnit: String, Hashable, Codable, Sendable, CaseIterable {
        case kilometers
        case miles

        var kilometersPerUnit: Decimal { self == .kilometers ? 1 : Decimal(string: "1.609344")! }

        var label: String {
            switch self {
            case .kilometers: String(localized: "km", bundle: .app, locale: .app, comment: "Abbreviation for kilometres")
            case .miles: String(localized: "mi", bundle: .app, locale: .app, comment: "Abbreviation for miles")
            }
        }
    }

    enum Problem: Error, Equatable, Sendable {
        case missingDuration
        case durationOutOfRange
        case invalidDistance
        case invalidCalories
        case startsInFuture
        case nameTooLong

        var message: String {
            switch self {
            case .missingDuration: String(localized: "Add how long it took.", bundle: .app, locale: .app)
            case .durationOutOfRange: String(localized: "Duration must be between 1 minute and 24 hours.", bundle: .app, locale: .app)
            case .invalidDistance: String(localized: "Distance must be a number above 0.", bundle: .app, locale: .app)
            case .invalidCalories: String(localized: "Calories must be a whole number from 1 to 20,000.", bundle: .app, locale: .app)
            case .startsInFuture: String(localized: "This activity can’t finish in the future. Check when it finished.", bundle: .app, locale: .app)
            case .nameTooLong: String(localized: "Use a name of 150 characters or fewer.", bundle: .app, locale: .app)
            }
        }
    }

    init(activity: WorkoutActivity, endedAt: Date = Date()) {
        self.activity = activity
        self.endedAt = endedAt
    }

    /// The same answers moved to another activity, keeping only what still
    /// applies. Time, effort, calories and notes mean the same for every
    /// activity; distance only where it is asked, and details never carry
    /// across -- a yoga style is not a tennis session type.
    func switching(to activity: WorkoutActivity) -> ActivityLogDraft {
        var draft = self
        draft.activity = activity
        draft.details = details.sanitized(for: activity)
        if activity.distanceField == .none { draft.distance = "" }
        return draft
    }

    var durationSeconds: Int? {
        let hours = Int(NumberInput.latinDigits(hours).trimmingCharacters(in: .whitespaces)) ?? 0
        let minutes = Int(NumberInput.latinDigits(minutes).trimmingCharacters(in: .whitespaces)) ?? 0
        guard hours > 0 || minutes > 0 else { return nil }
        return hours * 3600 + minutes * 60
    }

    mutating func setDuration(minutes total: Int) {
        hours = total >= 60 ? String(total / 60) : ""
        minutes = String(total % 60)
    }

    /// Kilometres from what was typed, in whichever unit it was typed in.
    /// Nil for blank; `.invalid` for anything that is not a positive number.
    var distanceKilometers: DistanceValue {
        let trimmed = NumberInput.latinDigits(distance).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty else { return .blank }
        guard let typed = Decimal(string: trimmed), typed > 0 else { return .invalid }
        var kilometers = typed * distanceUnit.kilometersPerUnit
        var rounded = Decimal()
        NSDecimalRound(&rounded, &kilometers, 3, .plain)
        guard rounded >= Decimal(string: "0.01")!, rounded <= Decimal(string: "9999.999")! else { return .invalid }
        return .value(rounded)
    }

    enum DistanceValue: Equatable {
        case blank
        case invalid
        case value(Decimal)
    }

    /// Pace or speed from the duration and distance typed so far, for the
    /// line under the distance field. Nil until both are there.
    var paceOrSpeedText: String? {
        guard let seconds = durationSeconds, case .value(let kilometers) = distanceKilometers else { return nil }
        let distance = NSDecimalNumber(decimal: kilometers).doubleValue
        guard distance > 0 else { return nil }
        let typedDistance = distance / NSDecimalNumber(decimal: distanceUnit.kilometersPerUnit).doubleValue
        switch activity.family {
        case .biking:
            let speed = typedDistance / (Double(seconds) / 3600)
            return String(
                localized: "Average speed \(String(format: "%.1f", speed)) \(distanceUnit.label)/h",
                bundle: .app,
                locale: .app,
                comment: "Speed worked out from distance and time, such as “Average speed 24.5 km/h”"
            )
        case .swimming:
            let perHundredMeters = Double(seconds) / (distance * 10)
            let total = Int(perHundredMeters.rounded())
            return String(
                localized: "Pace \(total / 60):\(String(format: "%02d", total % 60)) per 100 m",
                bundle: .app,
                locale: .app,
                comment: "Swim pace worked out from distance and time, such as “Pace 1:52 per 100 m”"
            )
        default:
            let perUnit = Int((Double(seconds) / typedDistance).rounded())
            return String(
                localized: "Pace \(perUnit / 60):\(String(format: "%02d", perUnit % 60)) per \(distanceUnit.label)",
                bundle: .app,
                locale: .app,
                comment: "Pace worked out from distance and time, such as “Pace 5:30 per km”"
            )
        }
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? activity.title : trimmed
    }

    /// What can be sent, or the first problem in the order the form shows
    /// the fields. Blank optional fields are left out rather than sent empty.
    func validated(now: Date = Date()) -> Result<ActivityLogEntry, Problem> {
        guard displayName.count <= 150 else { return .failure(.nameTooLong) }
        guard let duration = durationSeconds else { return .failure(.missingDuration) }
        guard Self.durationRange.contains(duration) else { return .failure(.durationOutOfRange) }
        // A few minutes of slack, as the server allows, for a phone clock
        // that runs a little ahead.
        guard endedAt <= now.addingTimeInterval(300) else {
            return .failure(.startsInFuture)
        }
        let distanceKilometers: Decimal?
        switch activity.distanceField == .none ? .blank : self.distanceKilometers {
        case .blank: distanceKilometers = nil
        case .invalid: return .failure(.invalidDistance)
        case .value(let value): distanceKilometers = value
        }
        let caloriesText = NumberInput.latinDigits(calories).trimmingCharacters(in: .whitespaces)
        let calories: Int?
        if caloriesText.isEmpty {
            calories = nil
        } else if let value = Int(caloriesText), Self.caloriesRange.contains(value) {
            calories = value
        } else {
            return .failure(.invalidCalories)
        }
        let notes = String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumNotesLength))
        return .success(ActivityLogEntry(
            activity: activity,
            workoutName: displayName,
            startedAt: endedAt.addingTimeInterval(-TimeInterval(duration)),
            durationSeconds: duration,
            perceivedEffort: perceivedEffort.map { min(max($0, 0), 100) },
            caloriesKilocalories: calories,
            distanceKilometers: distanceKilometers,
            details: details.sanitized(for: activity),
            notes: notes
        ))
    }
}

/// A logged activity ready to send: every value checked and in the units the
/// server stores.
nonisolated struct ActivityLogEntry: Hashable, Sendable {
    let activity: WorkoutActivity
    let workoutName: String
    let startedAt: Date
    let durationSeconds: Int
    let perceivedEffort: Int?
    /// The person's own estimate. Never presented as measured.
    let caloriesKilocalories: Int?
    let distanceKilometers: Decimal?
    let details: ActivityDetails
    let notes: String

    var endedAt: Date { startedAt.addingTimeInterval(TimeInterval(durationSeconds)) }
}

/// What was said about a session after it: how hard it felt, and the extras
/// the activity asks about. Saved onto a session recorded live, after Finish.
nonisolated struct SessionFeedback: Hashable, Sendable {
    var perceivedEffort: Int?
    var caloriesKilocalories: Int?
    var distanceKilometers: Decimal?
    var details = ActivityDetails()
    var notes = ""
}

/// Everything a finished session recorded beyond its sets, as read back from
/// the server: what history rows and the day's summary show.
///
/// Measured and entered values are kept apart. A distance from GPS or Apple
/// Health is a measurement; one typed in, and every calorie figure, is the
/// person's own estimate and is labelled as one wherever it is shown.
nonisolated struct SessionActivitySummary: Hashable, Sendable {
    var activity: WorkoutActivity?
    var perceivedEffort: Int?
    var manualCaloriesKilocalories: Int?
    var manualDistanceKilometers: Double?
    var measuredDistanceKilometers: Double?
    var details = ActivityDetails()
    var notes = ""
    var isManualEntry = false

    var hasAnything: Bool {
        perceivedEffort != nil || manualCaloriesKilocalories != nil || manualDistanceKilometers != nil
            || !details.isEmpty || !notes.isEmpty
    }

    /// The distance to show, preferring a measurement over an entry.
    var distanceKilometers: Double? { measuredDistanceKilometers ?? manualDistanceKilometers }
    var distanceIsMeasured: Bool { measuredDistanceKilometers != nil }
}

/// Whether a finished session trained, by the rule the server counts with.
nonisolated enum SessionTraining {
    /// Sets for anything planned as sets; time or distance for everything
    /// else. A session whose workout was deleted has no activity and is
    /// judged by its sets, as it always was.
    static func recordedSomething(
        activity: WorkoutActivity?,
        loggedSetCount: Int,
        durationSeconds: Double?,
        distanceKilometers: Double?
    ) -> Bool {
        guard let activity, !activity.usesSets else { return loggedSetCount > 0 }
        return (durationSeconds ?? 0) > 0 || (distanceKilometers ?? 0) > 0
    }
}

/// "1 h 05 min", "45 min".
nonisolated enum ActivityDurationText {
    static func text(seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 60 {
            return String(
                localized: "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min",
                bundle: .app,
                locale: .app,
                comment: "A duration in hours and minutes, such as “1 h 05 min”"
            )
        }
        return String(localized: "\(max(minutes, 1)) min", bundle: .app, locale: .app, comment: "A duration in minutes")
    }
}
