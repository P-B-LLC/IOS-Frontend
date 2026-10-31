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
        case .lifting: return String(localized: "Lifting", bundle: .app, locale: .app, comment: "A kind of workout: weight training")
        case .running: return String(localized: "Running", bundle: .app, locale: .app, comment: "A kind of workout")
        case .biking: return String(localized: "Biking", bundle: .app, locale: .app, comment: "A kind of workout: cycling")
        case .swimming: return String(localized: "Swimming", bundle: .app, locale: .app, comment: "A kind of workout")
        }
    }

    /// Distance types log a distance covered and a session time instead of
    /// weighted reps.
    var tracksDistance: Bool { self != .lifting }

    /// Plain-language label used when the action is the session itself rather
    /// than the saved workout name.
    var sessionTitle: String {
        switch self {
        case .lifting: return String(localized: "Strength session", bundle: .app, locale: .app)
        case .running: return String(localized: "Run session", bundle: .app, locale: .app)
        case .biking: return String(localized: "Ride session", bundle: .app, locale: .app)
        case .swimming: return String(localized: "Swim session", bundle: .app, locale: .app)
        }
    }

    /// How the logged distance is described for this type.
    var distanceTitle: String {
        switch self {
        case .running: return String(localized: "Distance ran", bundle: .app, locale: .app)
        case .biking: return String(localized: "Distance biked", bundle: .app, locale: .app)
        case .swimming: return String(localized: "Distance swum", bundle: .app, locale: .app)
        case .lifting: return String(localized: "Distance", bundle: .app, locale: .app)
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
        case .treadmill: return String(localized: "Treadmill", bundle: .app, locale: .app, comment: "A cardio machine")
        case .stationaryBike: return String(localized: "Bike", bundle: .app, locale: .app, comment: "A cardio machine: a stationary exercise bike")
        case .stairMaster: return String(localized: "Stair Master", bundle: .app, locale: .app, comment: "A cardio machine: a stair climber")
        case .elliptical: return String(localized: "Elliptical", bundle: .app, locale: .app, comment: "A cardio machine: an elliptical trainer")
        case .rowingMachine: return String(localized: "Rower", bundle: .app, locale: .app, comment: "A cardio machine: a rowing machine")
        case .assaultBike: return String(localized: "Assault Bike", bundle: .app, locale: .app, comment: "A cardio machine: a fan-resisted air bike")
        case .skiErg: return String(localized: "Ski Erg", bundle: .app, locale: .app, comment: "A cardio machine: a ski ergometer")
        case .other: return String(localized: "Other", bundle: .app, locale: .app, comment: "A cardio machine not in the list")
        }
    }

}

/// A single exercise within a workout (e.g. "Bench Press"), with a target
/// number of sets and how they are meant to be done. Reps and weight are
/// logged per-session later; the targets here are only what to aim for.
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
    /// The kind of each planned set, in order. Shorter than the set count
    /// when the last sets are normal, which is how the backend stores it.
    var setTypes: [WorkoutSetType]
    /// Seconds to rest after each set. Nil follows the person's default rest;
    /// zero means no timer for this exercise.
    var restSeconds: Int?
    /// Exercises sharing a number are a superset, done back to back.
    var supersetGroup: Int?
    var targetReps: Int?
    /// Decimal-string kilograms, like every weight on the wire.
    var targetWeightKilograms: String?

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        workoutExerciseID: Int? = nil,
        serverName: String? = nil,
        name: String,
        sets: Int? = 3,
        setTypes: [WorkoutSetType] = [],
        restSeconds: Int? = nil,
        supersetGroup: Int? = nil,
        targetReps: Int? = nil,
        targetWeightKilograms: String? = nil
    ) {
        self.id = id
        self.serverID = serverID
        self.workoutExerciseID = workoutExerciseID
        self.serverName = serverName
        self.name = name
        targetSets = sets
        self.setTypes = setTypes
        self.restSeconds = restSeconds
        self.supersetGroup = supersetGroup
        self.targetReps = targetReps
        self.targetWeightKilograms = targetWeightKilograms
    }

    /// The kind of every planned set, one per set.
    var plannedSetTypes: [WorkoutSetType] {
        (0..<max(sets, 0)).map { setTypes.indices.contains($0) ? setTypes[$0] : .normal }
    }

    mutating func setType(_ type: WorkoutSetType, at index: Int) {
        var types = plannedSetTypes
        guard types.indices.contains(index) else { return }
        types[index] = type
        setTypes = WorkoutStructureDiff.storedSetTypes(types)
    }

    private enum CodingKeys: String, CodingKey {
        case id, serverID, workoutExerciseID, serverName, name, targetSets
        case setTypes, restSeconds, supersetGroup, targetReps, targetWeightKilograms
    }

    // Written out so a draft saved before set kinds, rests and supersets
    // existed still opens. Recovery keeps drafts across app updates, and a
    // missing key would otherwise fail the whole draft.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        serverID = try values.decodeIfPresent(Int.self, forKey: .serverID)
        workoutExerciseID = try values.decodeIfPresent(Int.self, forKey: .workoutExerciseID)
        serverName = try values.decodeIfPresent(String.self, forKey: .serverName)
        name = try values.decode(String.self, forKey: .name)
        targetSets = try values.decodeIfPresent(Int.self, forKey: .targetSets)
        setTypes = try values.decodeIfPresent([WorkoutSetType].self, forKey: .setTypes) ?? []
        restSeconds = try values.decodeIfPresent(Int.self, forKey: .restSeconds)
        supersetGroup = try values.decodeIfPresent(Int.self, forKey: .supersetGroup)
        targetReps = try values.decodeIfPresent(Int.self, forKey: .targetReps)
        targetWeightKilograms = try values.decodeIfPresent(String.self, forKey: .targetWeightKilograms)
    }
}

/// A catalog result, not a workout relation. IDs remain server-owned.
nonisolated struct WorkoutExerciseChoice: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let muscleGroup: String
    /// Created by this account rather than part of the shared catalogue. The
    /// server only ever returns the reader's own custom exercises.
    var isCustom: Bool = false
}

nonisolated struct WorkoutExercisePage: Sendable {
    let items: [WorkoutExerciseChoice]
    let nextPage: Int?
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
    /// The activity's family, which old builds read; set with `activity`.
    private(set) var type: WorkoutType
    /// What this workout actually is: tennis, a hike, a lifting day.
    var activity: WorkoutActivity {
        didSet { type = activity.family }
    }
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
        activity: WorkoutActivity? = nil,
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
        let activity = activity ?? WorkoutActivity.legacyDefault(for: type)
        self.activity = activity
        self.type = activity.family
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

    /// Logged as time (and distance, where it has one) rather than as sets.
    /// True for every activity that is not sets-based: a tennis match is
    /// timed like a run, it just has no route. GPS is `activity.tracksRoute`.
    var tracksDistance: Bool { !activity.usesSets }

    private enum CodingKeys: String, CodingKey {
        case id, serverID, scheduleID, scheduledDate, name, type, activity
        case cardioMachine, cardioTargetMinutes, recurrenceID, exercises
    }

    // Written out so a draft recovered from a build before activities existed
    // still opens, as the activity its type always meant.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        serverID = try values.decodeIfPresent(Int.self, forKey: .serverID)
        scheduleID = try values.decodeIfPresent(Int.self, forKey: .scheduleID)
        scheduledDate = try values.decodeIfPresent(String.self, forKey: .scheduledDate)
        name = try values.decode(String.self, forKey: .name)
        let type = try values.decode(WorkoutType.self, forKey: .type)
        let activity = try values.decodeIfPresent(WorkoutActivity.self, forKey: .activity)
            ?? WorkoutActivity.legacyDefault(for: type)
        self.activity = activity
        self.type = activity.family
        cardioMachine = try values.decodeIfPresent(CardioMachine.self, forKey: .cardioMachine)
        cardioTargetMinutes = try values.decodeIfPresent(Int.self, forKey: .cardioTargetMinutes)
        recurrenceID = try values.decodeIfPresent(Int.self, forKey: .recurrenceID)
        exercises = try values.decode([Exercise].self, forKey: .exercises)
    }
}

/// One editable set while a workout session is in progress. Weight remains a
/// string so decimal precision is preserved when this draft is mapped to the
/// backend's decimal-string `weight_kg` field.
nonisolated struct WorkoutSetDraft: Identifiable, Hashable, Codable, Sendable {
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
    /// What this set is for. Logged with it, so history keeps the kind.
    var setType: WorkoutSetType

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        setNumber: Int,
        weightKilograms: String = "",
        reps: String = "",
        distanceKilometers: String = "",
        isLogged: Bool = false,
        setType: WorkoutSetType = .normal
    ) {
        self.id = id
        self.serverID = serverID
        self.setNumber = setNumber
        self.weightKilograms = weightKilograms
        self.reps = reps
        self.distanceKilometers = distanceKilometers
        self.isLogged = isLogged
        self.setType = setType
    }

    private enum CodingKeys: String, CodingKey {
        case id, serverID, setNumber, weightKilograms, reps, distanceKilometers, isLogged, setType
    }

    // A session checkpointed by an earlier build has no set kinds. Reading
    // them as normal keeps that session, and every set in it, recoverable
    // after an update installed mid-workout.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        serverID = try values.decodeIfPresent(Int.self, forKey: .serverID)
        setNumber = try values.decode(Int.self, forKey: .setNumber)
        weightKilograms = try values.decode(String.self, forKey: .weightKilograms)
        reps = try values.decode(String.self, forKey: .reps)
        distanceKilometers = try values.decodeIfPresent(String.self, forKey: .distanceKilometers) ?? ""
        isLogged = try values.decode(Bool.self, forKey: .isLogged)
        setType = try values.decodeIfPresent(WorkoutSetType.self, forKey: .setType) ?? .normal
    }

    /// Matches the OAS decimal-string contract (up to five integer digits and
    /// two fractional digits). Weight is nullable, so a blank bodyweight entry
    /// is valid.
    var isWeightValid: Bool {
        let value = weightKilograms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return true }
        return Decimal(string: value) != nil && value.range(
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
    let activity: WorkoutActivity
    /// The saved structure of this workout, used to seed a new lifting day.
    let exercises: [Exercise]
    var cardioMachine: CardioMachine?
    var cardioTargetMinutes: Int?
    /// When it was last trained, as the server counts it: the latest finished
    /// session that recorded a set. Nil when it never has been.
    var lastPerformedAt: Date?

    init(
        serverID: Int,
        name: String,
        type: WorkoutType,
        activity: WorkoutActivity? = nil,
        exercises: [Exercise] = [],
        cardioMachine: CardioMachine? = nil,
        cardioTargetMinutes: Int? = nil,
        lastPerformedAt: Date? = nil
    ) {
        self.serverID = serverID
        self.name = name
        let activity = activity ?? WorkoutActivity.legacyDefault(for: type)
        self.activity = activity
        self.type = activity.family
        self.exercises = exercises
        self.cardioMachine = cardioMachine
        self.cardioTargetMinutes = cardioTargetMinutes
        self.lastPerformedAt = lastPerformedAt
    }

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }

    /// The same plan as a workout draft, for editing or copying it. The rows
    /// keep their ids, so an edit updates them rather than replacing them.
    var asWorkout: Workout {
        // Marked in its first byte. A scheduled workout's id is derived from
        // its schedule row, and a schedule and a template can share a number.
        var identity = UUID.stable(forServerID: serverID).uuid
        identity.0 = 0x54
        return Workout(
            id: UUID(uuid: identity),
            serverID: serverID,
            name: name,
            type: type,
            activity: activity,
            cardioMachine: cardioMachine,
            cardioTargetMinutes: cardioTargetMinutes,
            exercises: exercises
        )
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
            case .heaviestWeight: return String(localized: "Heaviest Lift", bundle: .app, locale: .app, comment: "A kind of personal record")
            case .estimatedOneRepMax: return String(localized: "Best Est. 1RM", bundle: .app, locale: .app, comment: "A kind of personal record: the best estimated one-rep max")
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

    var valueText: String { valueText(in: .metric) }

    /// The record in the unit being shown. Records are kilograms from the
    /// server, like every weight, and are only converted here to be read.
    func valueText(in unit: WorkoutWeightUnit) -> String {
        guard unit == .metric else { return unit.formatted(kilograms: Self.decimal(valueKilograms)) }
        return String(
            localized: "\(Self.kilogramFigure(valueKilograms)) kg",
            bundle: .app,
            locale: .app,
            comment: "A weight; kg is the abbreviation for kilograms"
        )
    }

    /// How much this beat the old best by, e.g. "+2.5 kg".
    var improvementText: String? { improvementText(in: .metric) }

    func improvementText(in unit: WorkoutWeightUnit) -> String? {
        guard let previousValueKilograms else { return nil }
        let delta = valueKilograms - previousValueKilograms
        guard delta > 0 else { return nil }
        guard unit == .metric else {
            return String(
                localized: "+\(unit.formatted(kilograms: Self.decimal(delta)))",
                bundle: .app,
                locale: .app,
                comment: "How much a personal record beat the old best by, such as +5 lb"
            )
        }
        return String(
            localized: "+\(Self.kilogramFigure(delta)) kg",
            bundle: .app,
            locale: .app,
            comment: "How much a personal record beat the old best by; kg is the abbreviation for kilograms"
        )
    }

    var detailText: String { detailText(in: .metric) }

    func detailText(in unit: WorkoutWeightUnit) -> String {
        if isFirstEver {
            return reps.map { String(localized: "First time · \($0) reps", bundle: .app, locale: .app) }
                ?? String(localized: "First time", bundle: .app, locale: .app)
        }
        let previous = previousValueKilograms.map { value -> String in
            guard unit == .metric else {
                return String(
                    localized: "was \(unit.formatted(kilograms: Self.decimal(value)))",
                    bundle: .app,
                    locale: .app,
                    comment: "The old best a personal record beat, such as “was 180 lb”"
                )
            }
            return String(
                localized: "was \(Self.kilogramFigure(value)) kg",
                bundle: .app,
                locale: .app,
                comment: "The old best a personal record beat; kg is the abbreviation for kilograms"
            )
        } ?? ""
        guard let reps else { return previous }
        return String(
            localized: "\(reps) reps · \(previous)",
            bundle: .app,
            locale: .app,
            comment: "The second placeholder is the old best, such as “was 80 kg”"
        )
    }

    /// The server sends records as numbers; two decimals is all a stored
    /// weight ever has, so this loses nothing.
    private static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.2f", value)) ?? Decimal(value)
    }

    /// One decimal, dropped when it is zero: "82.5", but "80" rather than "80.0".
    private static func kilogramFigure(_ value: Double) -> String {
        let figure = String(format: "%.1f", value)
        return figure.hasSuffix(".0") ? String(figure.dropLast(2)) : figure
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

    /// The same pace without its unit, "8:51", for a figure whose unit is
    /// printed beside it.
    static func paceFigure(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0, seconds.isFinite else { return nil }
        return ImperialUnits.paceFigure(secondsPerKilometer: seconds)
    }

    /// Formats a duration as m:ss, used for split times.
    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The set-entry rows for one planned exercise in an active session.
nonisolated struct SessionExerciseDraft: Identifiable, Hashable, Codable, Sendable {
    let id: Exercise.ID
    let exerciseServerID: Int
    let sessionExerciseID: Int
    let name: String
    var sets: [WorkoutSetDraft]
    /// The saved workout's row this exercise came from. Nil for an exercise
    /// added during the session; that is how finishing tells the two apart.
    var workoutExerciseID: Int?
    /// Seconds to rest after each set. Nil follows the default rest.
    var restSeconds: Int?
    var supersetGroup: Int?
    var targetReps: Int?
    var targetWeightKilograms: String?

    init(
        id: Exercise.ID,
        exerciseServerID: Int,
        sessionExerciseID: Int,
        name: String,
        sets: [WorkoutSetDraft],
        workoutExerciseID: Int? = nil,
        restSeconds: Int? = nil,
        supersetGroup: Int? = nil,
        targetReps: Int? = nil,
        targetWeightKilograms: String? = nil
    ) {
        self.id = id
        self.exerciseServerID = exerciseServerID
        self.sessionExerciseID = sessionExerciseID
        self.name = name
        self.sets = sets
        self.workoutExerciseID = workoutExerciseID
        self.restSeconds = restSeconds
        self.supersetGroup = supersetGroup
        self.targetReps = targetReps
        self.targetWeightKilograms = targetWeightKilograms
    }

    /// The target a set aims at. Targets describe the working sets, so a
    /// warm-up has none: offering 60 kg × 8 on a warm-up row would log a full
    /// working set as preparation with one tap.
    func targetReps(for set: WorkoutSetDraft) -> Int? {
        set.setType.countsAsWorkingSet ? targetReps : nil
    }

    func targetWeightKilograms(for set: WorkoutSetDraft) -> String? {
        guard set.setType.countsAsWorkingSet,
              let weight = targetWeightKilograms, !weight.isEmpty else { return nil }
        return weight
    }

    var loggedCount: Int { sets.filter(\.isLogged).count }
    var isComplete: Bool { !sets.isEmpty && sets.allSatisfy(\.isLogged) }
    /// The set to do next: the first one not yet logged.
    var currentSet: WorkoutSetDraft? { sets.first { !$0.isLogged } }

    /// Set numbers are the server's key for a set, so a new one takes the next
    /// unused number rather than the count: after a set is deleted from the
    /// middle, the count would reuse a number a logged set still holds.
    var nextSetNumber: Int { (sets.map(\.setNumber).max() ?? 0) + 1 }

    private enum CodingKeys: String, CodingKey {
        case id, exerciseServerID, sessionExerciseID, name, sets
        case workoutExerciseID, restSeconds, supersetGroup, targetReps, targetWeightKilograms
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Exercise.ID.self, forKey: .id)
        exerciseServerID = try values.decode(Int.self, forKey: .exerciseServerID)
        sessionExerciseID = try values.decode(Int.self, forKey: .sessionExerciseID)
        name = try values.decode(String.self, forKey: .name)
        sets = try values.decode([WorkoutSetDraft].self, forKey: .sets)
        workoutExerciseID = try values.decodeIfPresent(Int.self, forKey: .workoutExerciseID)
        restSeconds = try values.decodeIfPresent(Int.self, forKey: .restSeconds)
        supersetGroup = try values.decodeIfPresent(Int.self, forKey: .supersetGroup)
        targetReps = try values.decodeIfPresent(Int.self, forKey: .targetReps)
        targetWeightKilograms = try values.decodeIfPresent(String.self, forKey: .targetWeightKilograms)
    }
}

/// App-facing state for the single API workout session currently being logged.
/// Both local view identity and the backend integer session ID are retained.
nonisolated struct ActiveWorkoutSession: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let serverID: Int
    let day: Weekday
    let workoutID: Workout.ID
    let workoutServerID: Int
    let workoutName: String
    /// Decides whether this session logs distance or weighted reps.
    let workoutType: WorkoutType
    /// What is being done. Recovered sessions from before activities read as
    /// their type's activity.
    let activity: WorkoutActivity
    let startedAt: Date
    var exercises: [SessionExerciseDraft]
    /// The rest in progress, if any. Part of the session so it is saved in
    /// the same checkpoint: leaving the screen, switching apps or relaunching
    /// all come back to the same countdown.
    var restTimer: RestTimer?
    /// The saved workout's shape when this session started. Nil for a session
    /// recovered from a build that did not record it, which then simply does
    /// not offer to update the plan.
    var plan: WorkoutStructure?
    /// The exercise being worked on, shared by the screen and the Lock Screen
    /// so both point at the same next set.
    var focusedExerciseID: Exercise.ID?
    /// Set when the order changed here but the server has not confirmed it.
    var orderNeedsSync: Bool

    init(
        id: UUID,
        serverID: Int,
        day: Weekday,
        workoutID: Workout.ID,
        workoutServerID: Int,
        workoutName: String,
        workoutType: WorkoutType,
        activity: WorkoutActivity? = nil,
        startedAt: Date,
        exercises: [SessionExerciseDraft],
        restTimer: RestTimer? = nil,
        plan: WorkoutStructure? = nil,
        focusedExerciseID: Exercise.ID? = nil,
        orderNeedsSync: Bool = false
    ) {
        self.id = id
        self.serverID = serverID
        self.day = day
        self.workoutID = workoutID
        self.workoutServerID = workoutServerID
        self.workoutName = workoutName
        self.workoutType = workoutType
        self.activity = activity ?? WorkoutActivity.legacyDefault(for: workoutType)
        self.startedAt = startedAt
        self.exercises = exercises
        self.restTimer = restTimer
        self.plan = plan
        self.focusedExerciseID = focusedExerciseID
        self.orderNeedsSync = orderNeedsSync
    }

    /// Timed rather than logged as sets. See `Workout.tracksDistance`.
    var tracksDistance: Bool { !activity.usesSets }

    var totalSetCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var loggedSetCount: Int {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.isLogged).count
        }
    }

    var completedExerciseCount: Int { exercises.filter(\.isComplete).count }

    /// The session's shape now, in the same terms as `plan`.
    var structure: WorkoutStructure {
        WorkoutStructure(items: exercises.map {
            WorkoutStructure.Item(
                workoutExerciseID: $0.workoutExerciseID,
                exerciseServerID: $0.exerciseServerID,
                name: $0.name,
                setTypes: $0.sets.map(\.setType),
                restSeconds: $0.restSeconds,
                supersetGroup: $0.supersetGroup
            )
        })
    }

    /// How the session has been reshaped since it started. Empty when there is
    /// no plan to compare with.
    var structureChanges: [WorkoutStructureChange] {
        guard let plan else { return [] }
        return WorkoutStructureDiff.changes(from: plan, to: structure)
    }

    /// Total weight moved in the sets logged so far, in kilograms.
    var loggedVolumeKilograms: Decimal {
        exercises.flatMap(\.sets).reduce(Decimal.zero) { total, set in
            guard set.isLogged, set.setType.countsAsWorkingSet,
                  let weight = Decimal(string: set.weightKilograms),
                  let reps = Int(set.reps) else { return total }
            return total + weight * Decimal(reps)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, serverID, day, workoutID, workoutServerID, workoutName, workoutType, activity, startedAt, exercises
        case restTimer, plan, focusedExerciseID, orderNeedsSync
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        serverID = try values.decode(Int.self, forKey: .serverID)
        day = try values.decode(Weekday.self, forKey: .day)
        workoutID = try values.decode(Workout.ID.self, forKey: .workoutID)
        workoutServerID = try values.decode(Int.self, forKey: .workoutServerID)
        workoutName = try values.decode(String.self, forKey: .workoutName)
        workoutType = try values.decode(WorkoutType.self, forKey: .workoutType)
        activity = try values.decodeIfPresent(WorkoutActivity.self, forKey: .activity)
            ?? WorkoutActivity.legacyDefault(for: workoutType)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        exercises = try values.decode([SessionExerciseDraft].self, forKey: .exercises)
        restTimer = try values.decodeIfPresent(RestTimer.self, forKey: .restTimer)
        plan = try values.decodeIfPresent(WorkoutStructure.self, forKey: .plan)
        focusedExerciseID = try values.decodeIfPresent(Exercise.ID.self, forKey: .focusedExerciseID)
        orderNeedsSync = try values.decodeIfPresent(Bool.self, forKey: .orderNeedsSync) ?? false
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
    /// The days after this week that can be planned on, by `YYYY-MM-DD`.
    var upcoming: [String: [Workout]] = [:]
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
    /// Nil from a server that does not record kinds yet, read as normal.
    var setType: WorkoutSetType? = nil

    /// "60 × 8", or nil when the set carries neither number.
    var summary: String? {
        summary(in: .metric)
    }

    /// The same, with the weight in the unit being shown.
    func summary(in unit: WorkoutWeightUnit) -> String? {
        switch (weightKilograms, reps) {
        case let (weight?, reps?): "\(unit.display(kilograms: weight)) × \(reps)"
        case let (weight?, nil): unit.display(kilograms: weight)
        case let (nil, reps?): String(localized: "\(reps) reps", bundle: .app, locale: .app)
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
        var setsText: String { setsText(in: .metric) }

        /// The same in the unit being shown, with a warm-up or drop set
        /// marked by its letter so the line reads the way it was trained.
        func setsText(in unit: WorkoutWeightUnit) -> String {
            let parts = sets.compactMap { set -> String? in
                guard let summary = set.summary(in: unit) else { return nil }
                guard let badge = set.setType?.badge else { return summary }
                return "\(badge) \(summary)"
            }
            return parts.isEmpty
                ? String(localized: "No sets logged", bundle: .app, locale: .app)
                : parts.joined(separator: "  ·  ")
        }
    }

    let sessionID: Int
    let performedAt: Date
    let lines: [Line]

    var loggedSetCount: Int { lines.reduce(0) { $0 + $1.sets.count } }

    /// Total weight moved, for sessions that recorded any. Nil when nothing
    /// logged a weight, which is what a bodyweight day should show. Warm-ups
    /// are left out, as the server leaves them out of records and progress.
    var totalVolumeKilograms: Decimal? {
        let total = lines.reduce(Decimal.zero) { running, line in
            running + line.sets.reduce(Decimal.zero) { inner, set in
                guard set.setType?.countsAsWorkingSet != false,
                      let weight = set.weightKilograms, let reps = set.reps else {
                    return inner
                }
                return inner + weight * Decimal(reps)
            }
        }
        return total > 0 ? total : nil
    }
}

// MARK: - Exercise names as shown

// An exercise's `name` is what the server calls it and what every match and
// save goes by. These are what a screen shows instead: the library's
// translation when the name is one of its exercises, else the name as written.

extension Exercise {
    var displayName: String { ExerciseLibrary.displayName(name) }
}

extension WorkoutExerciseChoice {
    var displayName: String { ExerciseLibrary.displayName(name) }
}

extension SessionExerciseDraft {
    var displayName: String { ExerciseLibrary.displayName(name) }
}

extension SessionOverview.Line {
    var displayName: String { ExerciseLibrary.displayName(name) }
}

extension PersonalRecord {
    var exerciseDisplayName: String { ExerciseLibrary.displayName(exerciseName) }
}

extension LiftProgressSeries {
    var exerciseDisplayName: String { ExerciseLibrary.displayName(exerciseName) }
}
