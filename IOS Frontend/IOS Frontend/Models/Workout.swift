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

    var symbolName: String {
        switch self {
        case .lifting: return "figure.strengthtraining.traditional"
        case .running: return "figure.run"
        case .biking: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        }
    }

    /// Distance types log a distance covered and a session time instead of
    /// weighted reps.
    var tracksDistance: Bool { self != .lifting }

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

    var symbolName: String {
        switch self {
        case .treadmill: return "figure.run.treadmill"
        case .stationaryBike, .assaultBike: return "figure.indoor.cycle"
        case .stairMaster: return "figure.stair.stepper"
        case .elliptical: return "figure.elliptical"
        case .rowingMachine: return "figure.indoor.rowing"
        case .skiErg: return "figure.skiing.crosscountry"
        case .other: return "figure.mixed.cardio"
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
    let kilometer: Int
    let seconds: Double
    let distanceKilometers: Double

    var id: Int { kilometer }

    var isPartial: Bool { distanceKilometers < 0.995 }

    /// Pace for this split, normalized so a partial final kilometer is
    /// comparable with the full ones rather than looking impossibly fast.
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

    var elevationGainText: String? {
        guard let elevationGainMeters, elevationGainMeters > 0 else { return nil }
        return String(format: "%.0f m", elevationGainMeters)
    }

    var paceText: String? { Self.paceText(paceSecondsPerKilometer) }
    var movingPaceText: String? { Self.paceText(movingPaceSecondsPerKilometer) }

    var averageSpeedText: String? {
        guard let averageSpeedKilometersPerHour else { return nil }
        return String(format: "%.1f km/h", averageSpeedKilometersPerHour)
    }

    var maxSpeedText: String? {
        guard let maxSpeedKilometersPerHour else { return nil }
        return String(format: "%.1f km/h", maxSpeedKilometersPerHour)
    }

    var distanceText: String? {
        guard let distanceKilometers else { return nil }
        return String(format: "%.2f km", distanceKilometers)
    }

    /// Formats seconds-per-kilometer as "5:30 /km".
    static func paceText(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0, seconds.isFinite else { return nil }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d /km", total / 60, total % 60)
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

/// The seven days of the week, ordered Monday-first to match the weekly widget.
nonisolated enum Weekday: Int, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    /// Full display name, e.g. "Monday".
    var fullName: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }

    /// Short display name, e.g. "Mon".
    var shortName: String { String(fullName.prefix(3)) }

    /// The API's weekday number, which counts from Monday as zero to match
    /// Python's `date.weekday()`. This enum counts from one.
    var apiValue: Int { rawValue - 1 }

    /// Reads back a weekday sent by the API.
    init?(apiValue: Int) {
        self.init(rawValue: apiValue + 1)
    }

    /// Maps a `Calendar` weekday component (1 = Sunday … 7 = Saturday) to a `Weekday`.
    init?(calendarWeekday: Int) {
        switch calendarWeekday {
        case 1: self = .sunday
        case 2: self = .monday
        case 3: self = .tuesday
        case 4: self = .wednesday
        case 5: self = .thursday
        case 6: self = .friday
        case 7: self = .saturday
        default: return nil
        }
    }
}
