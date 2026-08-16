//
//  WorkoutAPIRepository.swift
//  IOS Frontend
//
//  OAS-generated workout, schedule, and session operations.
//

import Foundation
// Needed to build the null half of a nullable enum field, whose generated
// type is an OpenAPIRuntime value container.
import OpenAPIRuntime
import RepbaseAPI

actor WorkoutAPIRepository {
    private let configuration: APIConfiguration
    private let client: Client

    init(configuration: APIConfiguration, token: String) throws {
        self.configuration = configuration
        client = try RepbaseAPIClientFactory.makeAuthenticated(
            serverURL: configuration.serverURL,
            token: token,
            allowInsecureLocalhost: configuration.allowsInsecureLocalhost
        )
    }

    // MARK: - Week loading

    /// Every workout scheduled in the week, grouped by day. A date can carry
    /// more than one schedule, so each day maps to a list in schedule order
    /// rather than a single workout.
    func loadWeek(dateByDay: [Weekday: String]) async throws -> [Weekday: [Workout]] {
        // Fill the week in from the user's weekly repeats before reading it, so
        // a new week arrives already planned rather than empty. The server
        // leaves finished weeks alone, and adding a day it already planned is a
        // no-op, so this is safe on every load.
        if let weekStart = dateByDay[.monday] {
            try await planWeek(start: weekStart)
        }

        async let schedulesRequest = fetchAllSchedules()
        async let workoutsRequest = fetchAllWorkouts()
        async let recurrencesRequest = fetchAllRecurrences()
        let (schedules, templates, recurrences) = try await (
            schedulesRequest,
            workoutsRequest,
            recurrencesRequest
        )

        let dayByDate = Dictionary(
            uniqueKeysWithValues: dateByDay.map { ($0.value, $0.key) }
        )
        let templateByID = Dictionary(
            uniqueKeysWithValues: templates.map { ($0.id, $0) }
        )
        var recurrenceIDs: [String: Int] = [:]
        for rule in recurrences {
            let key = Self.recurrenceKey(
                workout: rule.workout,
                weekday: rule.weekday.value1.rawValue
            )
            recurrenceIDs[key] = rule.id
        }

        var result: [Weekday: [Workout]] = [:]
        for schedule in schedules.sorted(by: { $0.id < $1.id }) {
            guard let day = dayByDate[schedule.scheduledDate],
                  let template = templateByID[schedule.workout] else {
                continue
            }

            let exercises = template.exercises
                .sorted {
                    ($0.order ?? 1, $0.id) < ($1.order ?? 1, $1.id)
                }
                .map { relation in
                    Exercise(
                        serverID: relation.exercise,
                        workoutExerciseID: relation.id,
                        serverName: relation.exerciseName,
                        name: relation.exerciseName,
                        sets: Self.safeSetCount(relation.targetSets)
                    )
                }

            result[day, default: []].append(
                Workout(
                    serverID: template.id,
                    scheduleID: schedule.id,
                    scheduledDate: schedule.scheduledDate,
                    name: template.name,
                    type: Self.workoutType(from: template.workoutType),
                    cardioMachine: Self.cardioMachine(from: template.cardioMachine),
                    cardioTargetMinutes: template.cardioTargetMinutes.map(Int.init),
                    recurrenceID: recurrenceIDs[
                        Self.recurrenceKey(
                            workout: template.id,
                            weekday: day.apiValue
                        )
                    ],
                    exercises: exercises
                )
            )
        }
        return result
    }

    /// Identifies a repeat by the workout it schedules and the day it lands on,
    /// which is what the app has in hand when drawing a day.
    private static func recurrenceKey(workout: Int, weekday: Int) -> String {
        "\(workout)-\(weekday)"
    }

    /// Asks the server to turn this week's weekly repeats into scheduled days.
    private func planWeek(start: String) async throws {
        let output = try await client.schedulesPlanWeekCreate(
            body: .json(Components.Schemas.PlanWeekRequest(start: start))
        )
        switch output {
        case .ok:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Weekly repeats

    /// Makes a workout come back on this weekday every week, and returns the
    /// repeat's identifier.
    func startRepeating(_ workout: Workout, on day: Weekday) async throws -> Int {
        guard let templateID = workout.serverID else {
            throw APIServiceError.missingServerIdentifier("Workout")
        }

        let output = try await client.recurrencesCreate(
            body: .json(
                Components.Schemas.WorkoutRecurrenceRequest(
                    workout: templateID,
                    weekday: .init(value1: Self.weekdayPayload(day))
                )
            )
        )
        switch output {
        case .created(let response):
            return try response.body.json.id
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Stops a weekly repeat. The server clears the weeks it had planned ahead
    /// and leaves this week, and every finished week, exactly as they are.
    func stopRepeating(_ workout: Workout) async throws {
        guard let recurrenceID = workout.recurrenceID else {
            throw APIServiceError.missingServerIdentifier("Weekly repeat")
        }

        let output = try await client.recurrencesDestroy(
            path: .init(id: recurrenceID)
        )
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    private static func weekdayPayload(_ day: Weekday) -> Components.Schemas.WeekdayEnum {
        Components.Schemas.WeekdayEnum(rawValue: day.apiValue) ?? ._0
    }

    // MARK: - Workout planning

    func saveWorkout(
        _ draft: Workout,
        replacing existing: Workout?,
        scheduledDate: String
    ) async throws {
        if let existing, let workoutID = existing.serverID {
            try await updateWorkout(
                draft,
                existing: existing,
                workoutID: workoutID
            )
        } else {
            try await createWorkout(draft, scheduledDate: scheduledDate)
        }
    }

    func removeSchedule(_ workout: Workout) async throws {
        guard let scheduleID = workout.scheduleID else {
            throw APIServiceError.missingServerIdentifier("Workout schedule")
        }

        let output = try await client.schedulesDestroy(
            path: .init(id: scheduleID)
        )
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    private func createWorkout(
        _ draft: Workout,
        scheduledDate: String
    ) async throws {
        let template: Components.Schemas.WorkoutTemplate

        // Workout names are unique per user, and a template is meant to be
        // scheduled on as many days as the user likes. Reuse one they already
        // have by that name instead of failing on the uniqueness constraint.
        if let existing = try await fetchAllWorkouts().first(
            where: { Self.normalizedName($0.name) == Self.normalizedName(draft.name) }
        ) {
            template = existing
            try await scheduleWorkout(
                templateID: template.id,
                scheduledDate: scheduledDate
            )
            return
        }

        let templateOutput = try await client.workoutsCreate(
            body: .json(
                Components.Schemas.WorkoutTemplateRequest(
                    name: draft.name,
                    workoutType: Self.workoutTypePayload(draft.type),
                    cardioMachine: draft.cardioMachine
                        .flatMap(Self.cardioEnum)
                        .map { .CardioMachineEnum($0) }
                        ?? .NullEnum(.init()),
                    cardioTargetMinutes: draft.cardioTargetMinutes.map(Int64.init)
                )
            )
        )

        switch templateOutput {
        case .created(let response):
            template = try response.body.json
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }

        do {
            var catalog = try await fetchAllExercises()
            for (index, exercise) in draft.exercises.enumerated() {
                let exerciseID = try await resolveExercise(
                    exercise,
                    catalog: &catalog
                )
                let relationOutput = try await client.workoutExercisesCreate(
                    body: .json(
                        Components.Schemas.WorkoutExerciseRequest(
                            workout: template.id,
                            exercise: exerciseID,
                            order: Int64(index + 1),
                            targetSets: exercise.targetSets.map(Int64.init)
                        )
                    )
                )
                switch relationOutput {
                case .created:
                    break
                case .undocumented(let statusCode, _):
                    throw APIServiceError.undocumentedStatus(statusCode)
                }
            }

            try await scheduleWorkout(
                templateID: template.id,
                scheduledDate: scheduledDate
            )
        } catch {
            throw APIServiceError.partialWorkoutCreation(
                "The template exists on the server, but its exercises or date assignment need attention. \(error.localizedDescription)"
            )
        }
    }

    private func scheduleWorkout(
        templateID: Int,
        scheduledDate: String
    ) async throws {
        let output = try await client.schedulesCreate(
            body: .json(
                Components.Schemas.WorkoutScheduleRequest(
                    workout: templateID,
                    scheduledDate: scheduledDate
                )
            )
        )
        switch output {
        case .created:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Compares workout names the way a person would, so "Morning Run" and
    /// "morning run " are the same workout.
    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func updateWorkout(
        _ draft: Workout,
        existing: Workout,
        workoutID: Int
    ) async throws {
        let templateOutput = try await client.workoutsPartialUpdate(
            path: .init(id: workoutID),
            body: .json(
                Components.Schemas.PatchedWorkoutTemplateRequest(
                    name: draft.name,
                    workoutType: Self.workoutTypePayload(draft.type),
                    cardioMachine: draft.cardioMachine
                        .flatMap(Self.cardioEnum)
                        .map { .CardioMachineEnum($0) }
                        ?? .NullEnum(.init()),
                    cardioTargetMinutes: draft.cardioTargetMinutes.map(Int64.init)
                )
            )
        )
        switch templateOutput {
        case .ok:
            break
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }

        do {
            let retainedRelationIDs = Set(
                draft.exercises.compactMap(\.workoutExerciseID)
            )
            for removed in existing.exercises {
                guard let relationID = removed.workoutExerciseID,
                      !retainedRelationIDs.contains(relationID) else {
                    continue
                }
                let output = try await client.workoutExercisesDestroy(
                    path: .init(id: relationID)
                )
                switch output {
                case .noContent:
                    break
                case .undocumented(let statusCode, _):
                    throw APIServiceError.undocumentedStatus(statusCode)
                }
            }

            var catalog = try await fetchAllExercises()
            for (index, exercise) in draft.exercises.enumerated() {
                let exerciseID = try await resolveExercise(
                    exercise,
                    catalog: &catalog
                )

                if let relationID = exercise.workoutExerciseID {
                    let output = try await client.workoutExercisesPartialUpdate(
                        path: .init(id: relationID),
                        body: .json(
                            Components.Schemas.PatchedWorkoutExerciseRequest(
                                exercise: exerciseID,
                                order: Int64(index + 1),
                                targetSets: exercise.targetSets.map(Int64.init)
                            )
                        )
                    )
                    switch output {
                    case .ok:
                        break
                    case .undocumented(let statusCode, _):
                        throw APIServiceError.undocumentedStatus(statusCode)
                    }
                } else {
                    let output = try await client.workoutExercisesCreate(
                        body: .json(
                            Components.Schemas.WorkoutExerciseRequest(
                                workout: workoutID,
                                exercise: exerciseID,
                                order: Int64(index + 1),
                                targetSets: exercise.targetSets.map(Int64.init)
                            )
                        )
                    )
                    switch output {
                    case .created:
                        break
                    case .undocumented(let statusCode, _):
                        throw APIServiceError.undocumentedStatus(statusCode)
                    }
                }
            }
        } catch {
            throw APIServiceError.partialWorkoutCreation(
                "The workout name was saved, but one or more exercise changes failed. \(error.localizedDescription)"
            )
        }
    }

    private func resolveExercise(
        _ draft: Exercise,
        catalog: inout [Components.Schemas.Exercise]
    ) async throws -> Int {
        let normalizedName = Self.normalized(draft.name)
        if let serverID = draft.serverID,
           Self.normalized(draft.serverName ?? draft.name) == normalizedName {
            return serverID
        }
        if let match = catalog.first(
            where: { Self.normalized($0.name) == normalizedName }
        ) {
            return match.id
        }

        let output = try await client.exercisesCreate(
            body: .json(
                Components.Schemas.ExerciseRequest(name: draft.name)
            )
        )
        switch output {
        case .created(let response):
            let exercise = try response.body.json
            catalog.append(exercise)
            return exercise.id
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Workout sessions

    func startSession(
        for workout: Workout,
        on day: Weekday
    ) async throws -> ActiveWorkoutSession {
        guard let workoutServerID = workout.serverID else {
            throw APIServiceError.missingServerIdentifier("Workout")
        }

        let createOutput = try await client.sessionsCreate(
            body: .json(
                Components.Schemas.WorkoutSessionRequest(
                    workout: workoutServerID
                )
            )
        )
        let created: Components.Schemas.WorkoutSession
        switch createOutput {
        case .created(let response):
            created = try response.body.json
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }

        let startOutput = try await client.sessionsStartCreate(
            path: .init(id: created.id)
        )
        let started: Components.Schemas.WorkoutSession
        switch startOutput {
        case .ok(let response):
            started = try response.body.json
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }

        var sessionRelations = try await fetchAllSessionExercises()
            .filter { $0.session == created.id }
            .sorted { ($0.order ?? 1, $0.id) < ($1.order ?? 1, $1.id) }

        var exercises: [SessionExerciseDraft] = []
        for exercise in workout.exercises {
            guard let exerciseServerID = exercise.serverID,
                  let relationIndex = sessionRelations.firstIndex(
                    where: { $0.exercise == exerciseServerID }
                  ) else {
                throw APIServiceError.malformedResponse
            }
            let relation = sessionRelations.remove(at: relationIndex)
            exercises.append(
                SessionExerciseDraft(
                    id: exercise.id,
                    exerciseServerID: exerciseServerID,
                    sessionExerciseID: relation.id,
                    name: relation.exerciseName,
                    sets: Self.makeSetDrafts(count: exercise.sets)
                )
            )
        }

        return ActiveWorkoutSession(
            id: UUID(),
            serverID: started.id,
            day: day,
            workoutID: workout.id,
            workoutServerID: workoutServerID,
            workoutName: started.workoutName,
            workoutType: workout.type,
            startedAt: started.startedAt ?? Date(),
            exercises: exercises
        )
    }

    func logSet(
        _ set: WorkoutSetDraft,
        sessionExerciseID: Int,
        workoutType: WorkoutType
    ) async throws -> Int {
        let reps: Int64?
        let distanceKilometers: String?

        if workoutType.tracksDistance {
            // A run, ride, or swim is recorded as a distance; reps do not apply
            // and the elapsed time comes from the session's own start and end.
            let trimmedDistance = set.distanceKilometers
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDistance.isEmpty else {
                throw APIServiceError.malformedResponse
            }
            reps = nil
            distanceKilometers = trimmedDistance
        } else {
            guard let value = Int64(
                set.reps.trimmingCharacters(in: .whitespacesAndNewlines)
            ) else {
                throw APIServiceError.malformedResponse
            }
            reps = value
            distanceKilometers = nil
        }

        let trimmedWeight = set.weightKilograms
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let output = try await client.setEntriesCreate(
            body: .json(
                Components.Schemas.SetEntryRequest(
                    sessionExercise: sessionExerciseID,
                    setNumber: Int64(set.setNumber),
                    weightKg: trimmedWeight.isEmpty ? nil : trimmedWeight,
                    reps: reps,
                    distanceKm: distanceKilometers,
                    completedAt: Date()
                )
            )
        )
        switch output {
        case .created(let response):
            return try response.body.json.id
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Uploads a recorded GPS track. The response carries the session with the
    /// server's own distance and pace, which is what the app displays; the
    /// device never computes either.
    @discardableResult
    func uploadRoute(
        _ points: [RoutePoint],
        sessionID: Int
    ) async throws -> SessionRouteSummary {
        guard !points.isEmpty else {
            throw APIServiceError.malformedResponse
        }

        let payload = points.map { point in
            Components.Schemas.SessionRoutePointRequest(
                latitude: Self.coordinateString(point.latitude),
                longitude: Self.coordinateString(point.longitude),
                recordedAt: point.recordedAt,
                speedMps: point.speedMetersPerSecond.map {
                    String(format: "%.2f", max(0, $0))
                },
                altitudeM: point.altitudeMeters.map {
                    String(format: "%.2f", $0)
                }
            )
        }

        let output = try await client.sessionsRouteCreate(
            path: .init(id: sessionID),
            body: .json(
                Components.Schemas.SessionRouteUploadRequest(points: payload)
            )
        )
        switch output {
        case .ok(let response):
            let session = try response.body.json
            return SessionRouteSummary(
                distanceKilometers: session.routeDistanceKm,
                paceSecondsPerKilometer: session.paceSecondsPerKm,
                movingPaceSecondsPerKilometer: session.movingPaceSecondsPerKm,
                averageSpeedKilometersPerHour: session.averageSpeedKmh,
                maxSpeedKilometersPerHour: session.maxSpeedKmh,
                movingSeconds: session.movingSeconds,
                elevationGainMeters: session.elevationGainM,
                elevationLossMeters: session.elevationLossM,
                splits: (session.splits ?? []).map {
                    SessionSplit(
                        kilometer: Int($0.kilometer ?? 0),
                        seconds: $0.seconds ?? 0,
                        distanceKilometers: $0.distanceKm ?? 1
                    )
                }
            )
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Six decimal places is roughly a tenth of a metre and matches the
    /// contract's `^-?\d{0,3}(?:\.\d{0,6})?$` style decimal strings.
    private static func coordinateString(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    /// Every workout the user has created, for offering as a name to reuse.
    func workoutLibrary() async throws -> [WorkoutSummary] {
        try await fetchAllWorkouts()
            .map {
                WorkoutSummary(
                    serverID: $0.id,
                    name: $0.name,
                    type: Self.workoutType(from: $0.workoutType),
                    exercises: $0.exercises
                        .sorted {
                            ($0.order ?? 1, $0.id) < ($1.order ?? 1, $1.id)
                        }
                        .map { relation in
                            Exercise(
                                serverID: relation.exercise,
                                serverName: relation.exerciseName,
                                name: relation.exerciseName,
                                sets: Self.safeSetCount(relation.targetSets)
                            )
                        }
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// How an exercise has progressed over every set ever logged for it.
    ///
    /// The server returns each set; they are grouped into days here so a
    /// chart shows one point per training day rather than one per set. The
    /// weights and volumes themselves are the server's numbers.
    func liftProgress(
        exerciseID: Int,
        exerciseName: String,
        workoutName: String
    ) async throws -> LiftProgressSeries {
        let output = try await client.progressExercisesList(
            path: .init(exerciseId: exerciseID),
            query: .init(workoutName: workoutName)
        )
        let points: [Components.Schemas.ExerciseProgressPoint]
        switch output {
        case .ok(let response):
            points = try response.body.json
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }

        // Grouped by session rather than by date: two workouts trained on the
        // same day are two points, not one.
        var bySession: [Int: (date: Date, heaviest: Double, volume: Double)] = [:]

        for point in points {
            guard let weight = Double(point.weightKg),
                  let volume = Double(point.volumeKg) else {
                continue
            }
            var entry = bySession[point.session]
                ?? (date: point.completedAt, heaviest: 0, volume: 0)
            entry.date = min(entry.date, point.completedAt)
            entry.heaviest = max(entry.heaviest, weight)
            entry.volume += volume
            bySession[point.session] = entry
        }

        let days = bySession.values
            .map {
                LiftProgressSeries.Day(
                    date: $0.date,
                    heaviestKilograms: $0.heaviest,
                    volumeKilograms: $0.volume
                )
            }
            .sorted { $0.date < $1.date }

        return LiftProgressSeries(
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            days: days
        )
    }

    /// Records the cardio finisher performed after a session's exercises.
    ///
    /// Written onto the session that just finished rather than starting a new
    /// one, because a workout and the cardio after it are one training session.
    func recordCardio(
        sessionID: Int,
        machine: CardioMachine,
        seconds: Int,
        distanceKilometers: Double?
    ) async throws {
        // The request body declares its own enum for this field, distinct from
        // the one on the workout and session schemas.
        guard let machineValue = Components.Schemas.MachineEnum(
            rawValue: machine.rawValue
        ) else {
            throw APIServiceError.malformedResponse
        }

        let output = try await client.sessionsCardioCreate(
            path: .init(id: sessionID),
            body: .json(
                Components.Schemas.SessionCardioRequest(
                    machine: machineValue,
                    seconds: seconds,
                    distanceKm: distanceKilometers.map {
                        String(format: "%.3f", $0)
                    }
                )
            )
        )
        switch output {
        case .ok:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Records set during a session, as judged by the backend against every
    /// set logged before it.
    func personalRecords(sessionID: Int) async throws -> [PersonalRecord] {
        let output = try await client.sessionsRecordsList(
            path: .init(id: sessionID)
        )
        let records: [Components.Schemas.PersonalRecord]
        switch output {
        case .ok(let response):
            records = try response.body.json
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }

        return records.compactMap { record in
            let kind: PersonalRecord.Kind
            switch record.kind.value1 {
            case .heaviestWeight: kind = .heaviestWeight
            case .bestEstimated1rm: kind = .estimatedOneRepMax
            }
            return PersonalRecord(
                exerciseID: record.exercise,
                exerciseName: record.exerciseName,
                kind: kind,
                valueKilograms: record.value,
                previousValueKilograms: record.previousValue,
                reps: record.reps
            )
        }
    }

    /// Past completed sessions for a workout, newest first, for showing how a
    /// run has progressed. Only sessions that actually recorded a route are
    /// returned, since the rest have nothing to plot.
    func sessionHistory(
        workoutName: String,
        limit: Int = 20
    ) async throws -> [SessionHistoryPoint] {
        // Matched by name rather than by template id, so a workout's history
        // is everything the user called by that name.
        let output = try await client.sessionsList(
            query: .init(status: .completed, workoutName: workoutName)
        )
        let page: Components.Schemas.PaginatedWorkoutSessionList
        switch output {
        case .ok(let response):
            page = try response.body.json
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }

        return page.results
            .compactMap { session -> SessionHistoryPoint? in
                guard let endedAt = session.endedAt ?? session.startedAt,
                      let distance = session.routeDistanceKm,
                      distance > 0 else {
                    return nil
                }
                return SessionHistoryPoint(
                    sessionID: session.id,
                    date: endedAt,
                    distanceKilometers: distance,
                    paceSecondsPerKilometer: session.movingPaceSecondsPerKm
                        ?? session.paceSecondsPerKm,
                    elevationGainMeters: session.elevationGainM
                )
            }
            .sorted { $0.date < $1.date }
            .suffix(limit)
            .map { $0 }
    }

    func deleteSetEntry(id: Int) async throws {
        let output = try await client.setEntriesDestroy(path: .init(id: id))
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func endSession(id: Int) async throws {
        let output = try await client.sessionsEndCreate(path: .init(id: id))
        switch output {
        case .ok:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    func discardSession(id: Int) async throws {
        let output = try await client.sessionsDestroy(path: .init(id: id))
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    // MARK: - Pagination

    private func fetchAllRecurrences() async throws -> [Components.Schemas.WorkoutRecurrence] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [Components.Schemas.WorkoutRecurrence] = []
        repeat {
            let output = try await client.recurrencesList(query: .init(page: page))
            let response: Components.Schemas.PaginatedWorkoutRecurrenceList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results)
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    private func fetchAllSchedules() async throws -> [Components.Schemas.WorkoutSchedule] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [Components.Schemas.WorkoutSchedule] = []
        repeat {
            let output = try await client.schedulesList(query: .init(page: page))
            let response: Components.Schemas.PaginatedWorkoutScheduleList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results)
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    private func fetchAllWorkouts() async throws -> [Components.Schemas.WorkoutTemplate] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [Components.Schemas.WorkoutTemplate] = []
        repeat {
            let output = try await client.workoutsList(query: .init(page: page))
            let response: Components.Schemas.PaginatedWorkoutTemplateList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results)
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    private func fetchAllExercises() async throws -> [Components.Schemas.Exercise] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [Components.Schemas.Exercise] = []
        repeat {
            let output = try await client.exercisesList(query: .init(page: page))
            let response: Components.Schemas.PaginatedExerciseList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results)
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    private func fetchAllSessionExercises() async throws -> [Components.Schemas.SessionExercise] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [Components.Schemas.SessionExercise] = []
        repeat {
            let output = try await client.sessionExercisesList(
                query: .init(page: page)
            )
            let response: Components.Schemas.PaginatedSessionExerciseList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results)
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    private func nextPage(
        _ next: String?,
        visited: inout Set<Int>
    ) throws -> Int? {
        guard let next else { return nil }
        guard let url = URL(string: next, relativeTo: configuration.serverURL)?.absoluteURL,
              Self.sameOrigin(url, configuration.serverURL),
              let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ),
              let pageValue = components.queryItems?
                .first(where: { $0.name == "page" })?.value,
              let page = Int(pageValue),
              page > 0,
              visited.insert(page).inserted else {
            throw APIServiceError.untrustedPaginationURL
        }
        return page
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "https" ? 443 : 80
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func safeSetCount(_ value: Int64?) -> Int? {
        guard let value else { return nil }
        guard value >= 0, let count = Int(exactly: value) else { return 0 }
        return count
    }

    private static func makeSetDrafts(count: Int) -> [WorkoutSetDraft] {
        guard count > 0 else { return [] }
        return (1...count).map { WorkoutSetDraft(setNumber: $0) }
    }

    /// Maps the generated `workout_type` enum onto the app-facing type. An
    /// unrecognized or absent value falls back to lifting, matching the
    /// backend default for records created before the field existed.
    private static func workoutType(
        from value: Components.Schemas.WorkoutTypeEnum?
    ) -> WorkoutType {
        guard let value else { return .lifting }
        switch value {
        case .lifting: return .lifting
        case .running: return .running
        case .biking: return .biking
        case .swimming: return .swimming
        }
    }

    /// Reads a cardio finisher. Null means the workout ends with its exercises.
    private static func cardioMachine(
        from payload: Components.Schemas.WorkoutTemplate.CardioMachinePayload?
    ) -> CardioMachine? {
        guard let payload else { return nil }
        switch payload {
        case .CardioMachineEnum(let value):
            return CardioMachine(rawValue: value.rawValue)
        case .NullEnum:
            return nil
        }
    }

    private static func cardioEnum(
        _ machine: CardioMachine
    ) -> Components.Schemas.CardioMachineEnum? {
        Components.Schemas.CardioMachineEnum(rawValue: machine.rawValue)
    }

    private static func workoutTypePayload(
        _ type: WorkoutType
    ) -> Components.Schemas.WorkoutTypeEnum {
        switch type {
        case .lifting: return .lifting
        case .running: return .running
        case .biking: return .biking
        case .swimming: return .swimming
        }
    }
}
