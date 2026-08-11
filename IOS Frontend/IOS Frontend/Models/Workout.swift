//
//  Workout.swift
//  IOS Frontend
//
//  The core workout / exercise / weekday types.
//

import Foundation

/// A single exercise within a workout (e.g. "Bench Press"), with a target
/// number of sets. Reps and weight are logged per-session later, not here.
nonisolated struct Exercise: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var serverID: Int?
    var workoutExerciseID: Int?
    var serverName: String?
    var name: String
    /// Target number of sets for this exercise.
    var sets: Int

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        workoutExerciseID: Int? = nil,
        serverName: String? = nil,
        name: String,
        sets: Int = 3
    ) {
        self.id = id
        self.serverID = serverID
        self.workoutExerciseID = workoutExerciseID
        self.serverName = serverName
        self.name = name
        self.sets = sets
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
    /// The exercises that make up this workout, in order.
    var exercises: [Exercise]

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        scheduleID: Int? = nil,
        scheduledDate: String? = nil,
        name: String,
        exercises: [Exercise] = []
    ) {
        self.id = id
        self.serverID = serverID
        self.scheduleID = scheduleID
        self.scheduledDate = scheduledDate
        self.name = name
        self.exercises = exercises
    }

    /// Total number of sets across all exercises.
    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }
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
    var isLogged: Bool

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        setNumber: Int,
        weightKilograms: String = "",
        reps: String = "",
        isLogged: Bool = false
    ) {
        self.id = id
        self.serverID = serverID
        self.setNumber = setNumber
        self.weightKilograms = weightKilograms
        self.reps = reps
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

    var canBeLogged: Bool { isWeightValid && areRepsValid }
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
    let startedAt: Date
    var exercises: [SessionExerciseDraft]

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
