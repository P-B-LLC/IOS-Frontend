//
//  Workout.swift
//  IOS Frontend
//
//  The core workout / exercise / weekday types.
//

import Foundation

/// What kind of training a workout is. Mirrors the API `workout_type` values;
/// the raw values must stay in step with the generated `WorkoutTypeEnum`.
nonisolated enum WorkoutType: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case lifting
    case running
    case biking
    case swimming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lifting: return "Lifting"
        case .running: return "Running"
        case .biking: return "Biking"
        case .swimming: return "Swimming"
        }
    }

    /// Distance types log a distance covered and a session time instead of
    /// weighted reps.
    var tracksDistance: Bool { self != .lifting }

    /// Plain-language label used when the action is the session itself rather
    /// than the saved workout name.
    var sessionTitle: String {
        switch self {
        case .lifting: return "Strength session"
        case .running: return "Run session"
        case .biking: return "Ride session"
        case .swimming: return "Swim session"
        }
    }

    /// How the logged distance is described for this type.
    var distanceTitle: String {
        switch self {
        case .running: return "Distance ran"
        case .biking: return "Distance biked"
        case .swimming: return "Distance swum"
        case .lifting: return "Distance"
        }
    }
}

/// A machine a workout can finish on.
///
/// A finisher belongs to the workout it follows: it appears at the bottom of
/// that day's workout rather than as a second workout scheduled after it.
nonisolated enum CardioMachine: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case treadmill
    case stationaryBike = "stationary_bike"
    case stairMaster = "stair_master"
    case elliptical
    case rowingMachine = "rowing_machine"
    case assaultBike = "assault_bike"
    case skiErg = "ski_erg"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .treadmill: return "Treadmill"
        case .stationaryBike: return "Bike"
        case .stairMaster: return "Stair Master"
        case .elliptical: return "Elliptical"
        case .rowingMachine: return "Rower"
        case .assaultBike: return "Assault Bike"
        case .skiErg: return "Ski Erg"
        case .other: return "Other"
        }
    }

}

/// A single exercise within a workout (e.g. "Bench Press"), with a target
/// number of sets. Reps and weight are logged per-session later, not here.
nonisolated struct Exercise: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var serverID: Int?
    var workoutExerciseID: Int?
    var serverName: String?
    var name: String
    /// Optional OAS target_sets value. Nil and zero remain distinct.
    var targetSets: Int?
    var sets: Int {
        get { targetSets ?? 0 }
        set { targetSets = newValue }
    }

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        workoutExerciseID: Int? = nil,
        serverName: String? = nil,
        name: String,
        sets: Int? = 3
    ) {
        self.id = id
        self.serverID = serverID
        self.workoutExerciseID = workoutExerciseID
        self.serverName = serverName
        self.name = name
        targetSets = sets
    }
}

/// A workout the user builds and assigns to a day of the week (e.g. "Pull") —
/// a named group of exercises.
nonisolated struct Workout: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var serverID: Int?
    var scheduleID: Int?
    /// Literal OAS YYYY-MM-DD scheduled_date.
    var scheduledDate: String?
    var name: String
    /// Mirrors the API `workout_type`; existing records default to lifting.
    var type: WorkoutType
    /// Optional cardio to finish on. Part of this workout, not a second one.
    var cardioMachine: CardioMachine?
    /// How long the finisher is meant to last, if a target was set.
    var cardioTargetMinutes: Int?
    /// The weekly repeat that keeps this workout on this weekday, if any.
    /// Nil means it was planned for this date alone.
    var recurrenceID: Int?
    /// The exercises that make up this workout, in order.
    var exercises: [Exercise]

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        scheduleID: Int? = nil,
        scheduledDate: String? = nil,
        name: String,
        type: WorkoutType = .lifting,
        cardioMachine: CardioMachine? = nil,
        cardioTargetMinutes: Int? = nil,
        recurrenceID: Int? = nil,
        exercises: [Exercise] = []
    ) {
        self.id = id
        self.serverID = serverID
        self.scheduleID = scheduleID
        self.scheduledDate = scheduledDate
        self.name = name
        self.type = type
        self.cardioMachine = cardioMachine
        self.cardioTargetMinutes = cardioTargetMinutes
        self.recurrenceID = recurrenceID
        self.exercises = exercises
    }

    /// Whether this workout comes back on the same weekday every week.
    var repeatsWeekly: Bool { recurrenceID != nil }

    /// Whether this workout ends with cardio on a machine.
    var hasCardioFinisher: Bool { cardioMachine != nil }

    /// Total number of sets across all exercises.
    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }

    var tracksDistance: Bool { type.tracksDistance }
}

/// One editable set while a workout session is in progress. Weight remains a
/// string so decimal precision is preserved when this draft is mapped to the
/// backend's decimal-string `weight_kg` field.
nonisolated struct WorkoutSetDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    var serverID: Int?
    var setNumber: Int
    var weightKilograms: String
    var reps: String
    /// Distance covered, in kilometers, for running/biking/swimming efforts.
    /// Kept as a string so decimal precision survives the round trip to the
    /// backend's decimal-string `distance_km` field.
    var distanceKilometers: String
    var isLogged: Bool

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        setNumber: Int,
        weightKilograms: String = "",
        reps: String = "",
        distanceKilometers: String = "",
        isLogged: Bool = false
    ) {
        self.id = id
        self.serverID = serverID
        self.setNumber = setNumber
        self.weightKilograms = weightKilograms
        self.reps = reps
        self.distanceKilometers = distanceKilometers
        self.isLogged = isLogged
    }

    /// Matches the OAS decimal-string contract (up to five integer digits and
    /// two fractional digits). Weight is nullable, so a blank bodyweight entry
    /// is valid.
    var isWeightValid: Bool {
        let value = weightKilograms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return true }
        return value.range(
            of: #"^-?\d{0,5}(?:\.\d{0,2})?$"#,
            options: .regularExpression
        ) != nil
    }

    /// The interface requires reps before a set can be marked complete even
    /// though the API permits null reps for partially entered set records.
    var areRepsValid: Bool {
        let value = reps.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let integer = Int(value) else { return false }
        return integer >= 0
    }

    /// Matches the OAS decimal-string contract for `distance_km` (up to four
    /// integer digits and three fractional digits).
    var isDistanceValid: Bool {
        let value = distanceKilometers.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        guard value.range(
            of: #"^\d{0,4}(?:\.\d{0,3})?$"#,
            options: .regularExpression
        ) != nil else {
            return false
        }
        // The backend rejects anything below 0.01 km.
        return (Decimal(string: value) ?? 0) >= Decimal(string: "0.01")!
    }

    var canBeLogged: Bool { isWeightValid && areRepsValid }

    /// Distance efforts are logged on distance alone; reps and weight do not
    /// apply to a run, ride, or swim.
    var canBeLoggedAsDistance: Bool { isDistanceValid }

    func canBeLogged(as type: WorkoutType) -> Bool {
        type.tracksDistance ? canBeLoggedAsDistance : canBeLogged
    }
}

/// A workout the user has already created, offered when naming a new one.
///
/// Progress is gathered by name, so reusing an existing name keeps a workout's
/// history together while a near-miss spelling quietly starts a second one.
nonisolated struct WorkoutSummary: Identifiable, Hashable, Sendable {
    let serverID: Int
    let name: String
    let type: WorkoutType
    /// The saved structure of this workout, used to seed a new lifting day.
    let exercises: [Exercise]

    init(
        serverID: Int,
        name: String,
        type: WorkoutType,
        exercises: [Exercise] = []
    ) {
        self.serverID = serverID
        self.name = name
        self.type = type
        self.exercises = exercises
    }

    var id: Int { serverID }

    /// Names match the way the backend matches them: ignoring case and
    /// surrounding spaces.
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// How one exercise has progressed, as a series the backend supplies. Every
/// figure here is the server's; the app only groups them by day to plot.
nonisolated struct LiftProgressSeries: Identifiable, Hashable, Sendable {
    struct Day: Identifiable, Hashable, Sendable {
        let date: Date
        /// Heaviest single set that day.
        let heaviestKilograms: Double
        /// Everything lifted that day, weight times reps summed.
        let volumeKilograms: Double

        var id: Date { date }
    }

    let exerciseID: Int
    let exerciseName: String
    let days: [Day]

    var id: Int { exerciseID }

    var hasEnoughToPlot: Bool { days.count > 1 }
}

/// A best set during a session that beat everything logged before it.
nonisolated struct PersonalRecord: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// The heaviest single lift, which is what a lifter usually means.
        case heaviestWeight
        /// Epley estimate, which catches progress raw weight misses: five reps
        /// at 80 kg beats one at 85, but only the estimate shows it.
        case estimatedOneRepMax

        var title: String {
            switch self {
            case .heaviestWeight: return "Heaviest Lift"
            case .estimatedOneRepMax: return "Best Est. 1RM"
            }
        }
    }

    let exerciseID: Int
    let exerciseName: String
    let kind: Kind
    let valueKilograms: Double
    /// Nil the first time an exercise is logged, when everything is a first.
    let previousValueKilograms: Double?
    let reps: Int?

    var id: String { "\(exerciseID)-\(kind)" }

    var isFirstEver: Bool { previousValueKilograms == nil }

    var valueText: String {
        String(format: "%.1f kg", valueKilograms)
            .replacingOccurrences(of: ".0 kg", with: " kg")
    }

    /// How much this beat the old best by, e.g. "+2.5 kg".
    var improvementText: String? {
        guard let previousValueKilograms else { return nil }
        let delta = valueKilograms - previousValueKilograms
        guard delta > 0 else { return nil }
        return String(format: "+%.1f kg", delta)
            .replacingOccurrences(of: ".0 kg", with: " kg")
    }

    var detailText: String {
        if isFirstEver {
            return reps.map { "First time · \($0) reps" } ?? "First time"
        }
        let previous = previousValueKilograms.map {
            String(format: "was %.1f kg", $0)
                .replacingOccurrences(of: ".0 kg", with: " kg")
        } ?? ""
        guard let reps else { return previous }
        return "\(reps) reps · \(previous)"
    }
}

/// One finished run, ride, or swim, reduced to what a progress chart needs.
nonisolated struct SessionHistoryPoint: Identifiable, Hashable, Sendable {
    let sessionID: Int
    let date: Date
    let distanceKilometers: Double
    let paceSecondsPerKilometer: Double?
    let elevationGainMeters: Double?

    var id: Int { sessionID }
}

/// One kilometer of a session, as timed by the backend. The last split of a
/// run usually covers less than a kilometer.
nonisolated struct SessionSplit: Identifiable, Hashable, Sendable {
    /// 1 for the first mile, 2 for the second, and so on.
    let number: Int
    let seconds: Double
    /// Still kilometres. Every distance the server sends is, so a full mile
    /// split reads 1.609; it is converted only where it is shown.
    let distanceKilometers: Double

    var id: Int { number }

    /// Short of a full mile, which the last split usually is.
    var isPartial: Bool {
        distanceKilometers < (ImperialUnits.metersPerMile / 1000) - 0.005
    }

    /// Pace for this split, normalized so a partial final mile is comparable
    /// with the full ones rather than looking impossibly fast.
    var paceSecondsPerKilometer: Double? {
        guard distanceKilometers > 0 else { return nil }
        return seconds / distanceKilometers
    }
}

/// Distance, pace and speed for a session, exactly as the backend computed
/// them from the uploaded GPS track. None of it is calculated on the device.
nonisolated struct SessionRouteSummary: Hashable, Sendable {
    let distanceKilometers: Double?
    let paceSecondsPerKilometer: Double?
    let movingPaceSecondsPerKilometer: Double?
    let averageSpeedKilometersPerHour: Double?
    let maxSpeedKilometersPerHour: Double?
    let movingSeconds: Double?
    let elevationGainMeters: Double?
    let elevationLossMeters: Double?
    let splits: [SessionSplit]

    init(
        distanceKilometers: Double? = nil,
        paceSecondsPerKilometer: Double? = nil,
        movingPaceSecondsPerKilometer: Double? = nil,
        averageSpeedKilometersPerHour: Double? = nil,
        maxSpeedKilometersPerHour: Double? = nil,
        movingSeconds: Double? = nil,
        elevationGainMeters: Double? = nil,
        elevationLossMeters: Double? = nil,
        splits: [SessionSplit] = []
    ) {
        self.distanceKilometers = distanceKilometers
        self.paceSecondsPerKilometer = paceSecondsPerKilometer
        self.movingPaceSecondsPerKilometer = movingPaceSecondsPerKilometer
        self.averageSpeedKilometersPerHour = averageSpeedKilometersPerHour
        self.maxSpeedKilometersPerHour = maxSpeedKilometersPerHour
        self.movingSeconds = movingSeconds
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
        self.splits = splits
    }

    // Every figure below is stored in kilometres and metres, as the server
    // computed it, and converted only on the way to being read.

    var elevationGainText: String? {
        guard let elevationGainMeters, elevationGainMeters > 0 else { return nil }
        return ImperialUnits.elevationText(meters: elevationGainMeters)
    }

    var paceText: String? { Self.paceText(paceSecondsPerKilometer) }
    var movingPaceText: String? { Self.paceText(movingPaceSecondsPerKilometer) }

    var averageSpeedText: String? {
        guard let averageSpeedKilometersPerHour else { return nil }
        return ImperialUnits.speedText(kilometersPerHour: averageSpeedKilometersPerHour)
    }

    var maxSpeedText: String? {
        guard let maxSpeedKilometersPerHour else { return nil }
        return ImperialUnits.speedText(kilometersPerHour: maxSpeedKilometersPerHour)
    }

    var distanceText: String? {
        guard let distanceKilometers else { return nil }
        return ImperialUnits.distanceText(kilometers: distanceKilometers)
    }

    /// Formats seconds-per-kilometer as "8:51 /mi".
    static func paceText(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0, seconds.isFinite else { return nil }
        return ImperialUnits.paceText(secondsPerKilometer: seconds)
    }

    /// Formats a duration as m:ss, used for split times.
    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The set-entry rows for one planned exercise in an active session.
nonisolated struct SessionExerciseDraft: Identifiable, Hashable, Sendable {
    let id: Exercise.ID
    let exerciseServerID: Int
    let sessionExerciseID: Int
    let name: String
    var sets: [WorkoutSetDraft]
}

/// App-facing state for the single API workout session currently being logged.
/// Both local view identity and the backend integer session ID are retained.
nonisolated struct ActiveWorkoutSession: Identifiable, Hashable, Sendable {
    let id: UUID
    let serverID: Int
    let day: Weekday
    let workoutID: Workout.ID
    let workoutServerID: Int
    let workoutName: String
    /// Decides whether this session logs distance or weighted reps.
    let workoutType: WorkoutType
    let startedAt: Date
    var exercises: [SessionExerciseDraft]

    var tracksDistance: Bool { workoutType.tracksDistance }

    var totalSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var loggedSetCount: Int {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.isLogged).count
        }
    }
}

/// A completed session retained for immediate UI feedback. Its session and set
/// records have already been written through the generated API operations.
nonisolated struct CompletedWorkoutSession: Identifiable, Hashable, Sendable {
    let session: ActiveWorkoutSession
    let endedAt: Date

    var id: ActiveWorkoutSession.ID { session.id }
}

/// A week's schedule and the workout library, from one read.
///
/// The two used to be fetched separately and sequentially, which paged the
/// whole workout table twice per load for the same rows. They travel together
/// because they are built from the same templates.
nonisolated struct LoadedWeek: Sendable {
    var schedule: [Weekday: [Workout]]
    var library: [WorkoutSummary]
}

/// One set from the last time a workout was trained.
///
/// Shown as the hint in an empty field, so a set starts by saying what was
/// done last time rather than "0". It is never written into the field: what
/// gets logged has to be what the user actually lifted today.
nonisolated struct PreviousSet: Hashable, Sendable {
    let setNumber: Int
    let weightKilograms: Decimal?
    let reps: Int?

    /// "60 × 8", or nil when the set carries neither number.
    var summary: String? {
        switch (weightKilograms, reps) {
        case let (weight?, reps?): "\(weight.nutritionText) × \(reps)"
        case let (weight?, nil): weight.nutritionText
        case let (nil, reps?): "\(reps) reps"
        case (nil, nil): nil
        }
    }
}

/// What was actually logged in one finished session.
///
/// Read back from the server rather than remembered from the session that
/// wrote it, so a day trained last week reads the same as one trained a
/// minute ago.
nonisolated struct SessionOverview: Hashable, Sendable {
    nonisolated struct Line: Identifiable, Hashable, Sendable {
        let exerciseID: Int
        let name: String
        let sets: [PreviousSet]

        var id: Int { exerciseID }

        /// "60 × 8 · 60 × 8", the sets as they were logged.
        var setsText: String {
            let parts = sets.compactMap(\.summary)
            return parts.isEmpty ? "No sets logged" : parts.joined(separator: "  ·  ")
        }
    }

    let sessionID: Int
    let performedAt: Date
    let lines: [Line]

    var loggedSetCount: Int { lines.reduce(0) { $0 + $1.sets.count } }

    /// Total weight moved, for sessions that recorded any. Nil when nothing
    /// logged a weight, which is what a bodyweight day should show.
    var totalVolumeKilograms: Decimal? {
        let total = lines.reduce(Decimal.zero) { running, line in
            running + line.sets.reduce(Decimal.zero) { inner, set in
                guard let weight = set.weightKilograms, let reps = set.reps else {
                    return inner
                }
                return inner + weight * Decimal(reps)
            }
        }
        return total > 0 ? total : nil
    }
}
