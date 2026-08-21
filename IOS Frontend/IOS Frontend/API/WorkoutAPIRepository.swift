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
    func loadWeek(dateByDay: [Weekday: String]) async throws -> LoadedWeek {
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

        // Built from the templates already in hand. This used to be a second
        // call to workoutLibrary(), which paged the whole workout table a
        // second time, sequentially, for data this function had already read.
        let library = templates
            .map(Self.summary(from:))
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        return LoadedWeek(schedule: result, library: library)
    }

    /// One workout as the name-suggestion list wants it.
    private static func summary(
        from template: Components.Schemas.WorkoutTemplate
    ) -> WorkoutSummary {
        WorkoutSummary(
            serverID: template.id,
            name: template.name,
            type: workoutType(from: template.workoutType),
            exercises: template.exercises
                .sorted { ($0.order ?? 1, $0.id) < ($1.order ?? 1, $1.id) }
                .map { relation in
                    Exercise(
                        serverID: relation.exercise,
                        serverName: relation.exerciseName,
                        name: relation.exerciseName,
                        sets: safeSetCount(relation.targetSets)
                    )
                }
        )
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

    /// Puts a workout the user already has onto a date.
    ///
    /// Only a schedule row is written. Nothing about the template is touched:
    /// not its exercises, not the WorkoutExercise rows joining them, not the
    /// target sets, and it is never removed from wherever else it is planned.
    /// Reusing a saved workout is scheduling it, not rewriting it.
    func scheduleExistingWorkout(templateID: Int, on date: String) async throws {
        try await scheduleWorkout(templateID: templateID, scheduledDate: date)
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
        let templateID = try await createTemplate(draft)
        do {
            try await scheduleWorkout(
                templateID: templateID,
                scheduledDate: scheduledDate
            )
        } catch {
            throw APIServiceError.partialWorkoutCreation(
                "The template exists on the server, but its date assignment needs attention. \(error.localizedDescription)"
            )
        }
    }

    /// Creates a workout and its exercises, and answers with its server id.
    ///
    /// Nothing is put on the calendar. A rotation works out its own dates from
    /// its anchor, so a schedule row written here would land the workout on a
    /// day the cycle did not choose, and the cycle would then write its own
    /// alongside it.
    func createTemplate(_ draft: Workout) async throws -> Int {
        let template: Components.Schemas.WorkoutTemplate

        // Workout names are unique per user, and a template is meant to be
        // scheduled on as many days as the user likes. Reuse one they already
        // have by that name instead of failing on the uniqueness constraint.
        //
        // Reused as it stands: the exercises on screen are not written over
        // the saved ones. A rotation day is a choice of which workout goes
        // there, not a licence to rewrite a workout used elsewhere.
        if let existing = try await fetchAllWorkouts().first(
            where: { Self.normalizedName($0.name) == Self.normalizedName(draft.name) }
        ) {
            return existing.id
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
            var resolved: [String: Int] = [:]
            for (index, exercise) in draft.exercises.enumerated() {
                let exerciseID = try await resolveExercise(
                    exercise,
                    resolved: &resolved
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
        } catch {
            throw APIServiceError.partialWorkoutCreation(
                "The template exists on the server, but its exercises need attention. \(error.localizedDescription)"
            )
        }

        return template.id
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

            var resolved: [String: Int] = [:]
            for (index, exercise) in draft.exercises.enumerated() {
                let exerciseID = try await resolveExercise(
                    exercise,
                    resolved: &resolved
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

    /// The id of the exercise this draft names, creating it if the account has
    /// never used it.
    ///
    /// `resolved` carries the names settled earlier in the same save, so a
    /// workout listing an exercise twice asks the server once. Everything else
    /// is a single name lookup; the whole catalogue used to be paged down first
    /// to do this comparison on the phone.
    private func resolveExercise(
        _ draft: Exercise,
        resolved: inout [String: Int]
    ) async throws -> Int {
        let normalizedName = Self.normalized(draft.name)
        if let serverID = draft.serverID,
           Self.normalized(draft.serverName ?? draft.name) == normalizedName {
            return serverID
        }
        if let known = resolved[normalizedName] {
            return known
        }
        if let match = try await findExercise(named: draft.name) {
            resolved[normalizedName] = match.id
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
            resolved[Self.normalized(exercise.name)] = exercise.id
            return exercise.id
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// One exercise by name, or nil when the account has never used it.
    ///
    /// The server matches without regard to case or surrounding space, the same
    /// way `normalized` does, so the comparison no longer has to happen here
    /// over every row in the catalogue.
    private func findExercise(
        named name: String
    ) async throws -> Components.Schemas.Exercise? {
        let output = try await client.exercisesList(query: .init(name: name))
        switch output {
        case .ok(let response):
            return try response.body.json.results.first
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

        // Asked for by session. This used to read every session-exercise row
        // the account owns and filter here, so opening one session got slower
        // with every session ever logged.
        var sessionRelations = try await fetchSessionExercises(session: created.id)
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

    /// Totals, streaks and the six-week trend, counted by the server.
    ///
    /// `today` is the device's own date: week and month boundaries are cut
    /// against it rather than the server's clock, so the figures agree with
    /// the calendar the user is looking at.
    func trainingStats(today: Date = Date()) async throws -> TrainingStats {
        let output = try await client.sessionsTrainingStatsRetrieve(
            query: .init(today: Self.dayString(today))
        )
        switch output {
        case .ok(let response):
            let stats = try response.body.json
            return TrainingStats(
                totalWorkouts: stats.totalWorkouts,
                completedThisWeek: stats.completedThisWeek,
                completedThisMonth: stats.completedThisMonth,
                currentStreakWeeks: stats.currentStreakWeeks,
                bestStreakWeeks: stats.bestStreakWeeks,
                sixWeekCounts: stats.sixWeekCounts,
                weeklyGoal: stats.weeklyGoal
            )
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// `YYYY-MM-DD` in the device's own calendar.
    nonisolated static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    /// The GPS track a session recorded, in the order it was walked.
    ///
    /// Read back from the server rather than kept from the recording, so the
    /// map on a finished session draws the same track whether it was just
    /// stopped or opened from the history a month later.
    func route(sessionID: Int) async throws -> [RoutePoint] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [RoutePoint] = []
        repeat {
            let output = try await client.sessionsRouteList(
                path: .init(id: sessionID),
                query: .init(page: page)
            )
            let response: Components.Schemas.PaginatedSessionRoutePointList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results.compactMap(Self.routePoint(from:)))
            page = try nextPage(response.next, visited: &visited)
        } while page != nil
        return values
    }

    /// Coordinates cross as decimal strings, so a point the app cannot parse is
    /// dropped rather than drawn at the equator.
    private nonisolated static func routePoint(
        from payload: Components.Schemas.SessionRoutePoint
    ) -> RoutePoint? {
        guard let latitude = Double(payload.latitude),
              let longitude = Double(payload.longitude)
        else { return nil }

        return RoutePoint(
            latitude: latitude,
            longitude: longitude,
            recordedAt: payload.recordedAt ?? Date(),
            speedMetersPerSecond: payload.speedMps.flatMap(Double.init),
            altitudeMeters: payload.altitudeM.flatMap(Double.init)
        )
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
                        number: Int($0.number ?? 0),
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

    /// Completed sessions, newest first, for choosing one to post.
    ///
    /// All pages are followed rather than the first taken. The list declares no
    /// ordering, so a first page could as easily hold the oldest sessions as the
    /// newest, and a picker built on that assumption would quietly offer the
    /// wrong ones. Unlike `sessionHistory` this keeps sessions with no route:
    /// a lifting session has nothing to plot but is very much worth posting.
    ///
    /// `pageLimit` stops a picker from reading a training history of any length
    /// to fill a list nobody scrolls to the end of. It bounds the work without
    /// assuming an order: whatever those pages hold is still sorted by date
    /// before the newest are returned. Raising it costs a round-trip a page.
    /// The proper fix is an ordering parameter on the endpoint, which the
    /// contract does not have.
    func completedSessions(
        pageLimit: Int = 5,
        since: Date? = nil
    ) async throws -> [PostableSession] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [Components.Schemas.WorkoutSession] = []
        repeat {
            let output = try await client.sessionsList(
                query: .init(
                    page: page,
                    since: since.map(Self.dayString),
                    status: .completed
                )
            )
            let response: Components.Schemas.PaginatedWorkoutSessionList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            values.append(contentsOf: response.results)
            page = try nextPage(response.next, visited: &visited)
        } while page != nil && visited.count < pageLimit

        return values
            .compactMap { session -> PostableSession? in
                // Both timestamps are nullable. One with neither cannot be
                // placed in the list, and the date is what each row is sorted
                // and labelled by.
                guard let performedAt = session.endedAt ?? session.startedAt else {
                    return nil
                }
                return PostableSession(
                    sessionID: session.id,
                    workoutName: session.workoutName,
                    performedAt: performedAt,
                    durationSeconds: session.durationSeconds,
                    routeDistanceKilometers: session.routeDistanceKm,
                    // A string rather than the enum, because the session
                    // borrows it from a workout that may have been deleted.
                    // An unrecognised value is left nil rather than guessed.
                    workoutType: session.workoutType
                        .flatMap { WorkoutType(rawValue: $0) },
                    loggedSetCount: session.loggedSetCount
                )
            }
            .sorted { $0.performedAt > $1.performedAt }
    }

    // MARK: - Last time

    /// What was lifted the last time this workout was trained, by exercise id.
    ///
    /// Three requests whatever the workout holds: the session, its exercises,
    /// and its sets. The progress endpoint would have been one request per
    /// exercise, and each returns that exercise's entire history — every set
    /// ever logged — to read the last few rows of it.
    ///
    /// Matched by workout *name*, the way the rest of this file matches
    /// history, so "Push Day" recognises itself across the templates a repeat
    /// creates rather than only within one record.
    func previousSets(
        workoutName: String,
        excludingSessionID: Int?,
        pageLimit: Int = 3,
        sessionsToTry: Int = 5
    ) async throws -> [Int: [PreviousSet]] {
        // Walked back rather than taking the newest, because a session can be
        // started and finished without a single set being logged. Three such
        // Push Days in a row is real data from this account, and stopping at
        // the first would have shown nothing while a usable session sat just
        // behind them.
        let candidates = try await recentCompletedSessionIDs(
            workoutName: workoutName,
            excluding: excludingSessionID,
            pageLimit: pageLimit
        ).prefix(sessionsToTry)

        for sessionID in candidates {
            let sets = try await loggedSets(inSession: sessionID)
            if !sets.isEmpty { return sets }
        }
        return [:]
    }

    /// The sets logged in one session, by exercise. Empty when the session
    /// recorded nothing, which is what makes it worth skipping.
    private func loggedSets(
        inSession sessionID: Int
    ) async throws -> [Int: [PreviousSet]] {
        async let relationsRequest = fetchSessionExercises(session: sessionID)
        async let entriesRequest = fetchSetEntries(session: sessionID)
        let (relations, entries) = try await (relationsRequest, entriesRequest)

        // The sets name the row that joined an exercise to the session, not the
        // exercise, so that hop has to be undone before they can be looked up
        // by the exercise the screen is drawing.
        let exerciseByRelation = Dictionary(
            relations.map { ($0.id, $0.exercise) },
            uniquingKeysWith: { first, _ in first }
        )

        var result: [Int: [PreviousSet]] = [:]
        for entry in entries {
            guard let exerciseID = exerciseByRelation[entry.sessionExercise] else {
                continue
            }
            // A row with neither number is a set that was planned and never
            // logged. Counting it would make a session look usable and then
            // hint with blanks.
            guard entry.weightKg != nil || entry.reps != nil else { continue }
            result[exerciseID, default: []].append(
                PreviousSet(
                    setNumber: Int(entry.setNumber),
                    weightKilograms: entry.weightKg.flatMap { Decimal(string: $0) },
                    reps: entry.reps.map(Int.init)
                )
            )
        }
        for key in result.keys {
            result[key]?.sort { $0.setNumber < $1.setNumber }
        }
        return result
    }

    /// What was logged in one finished session, exercise by exercise.
    ///
    /// The same two reads the previous-set hints use, kept whole here rather
    /// than reduced to one set per exercise, because this is the record of the
    /// session itself and every set belongs in it.
    func sessionOverview(
        sessionID: Int,
        performedAt: Date
    ) async throws -> SessionOverview {
        async let relationsRequest = fetchSessionExercises(session: sessionID)
        async let entriesRequest = fetchSetEntries(session: sessionID)
        let (relations, entries) = try await (relationsRequest, entriesRequest)

        var setsByRelation: [Int: [PreviousSet]] = [:]
        for entry in entries {
            setsByRelation[entry.sessionExercise, default: []].append(
                PreviousSet(
                    setNumber: Int(entry.setNumber),
                    weightKilograms: entry.weightKg.flatMap { Decimal(string: $0) },
                    reps: entry.reps.map(Int.init)
                )
            )
        }

        let lines = relations
            .sorted { ($0.order ?? 1, $0.id) < ($1.order ?? 1, $1.id) }
            .map { relation in
                SessionOverview.Line(
                    exerciseID: relation.exercise,
                    name: relation.exerciseName,
                    sets: (setsByRelation[relation.id] ?? [])
                        .sorted { $0.setNumber < $1.setNumber }
                )
            }

        return SessionOverview(
            sessionID: sessionID,
            performedAt: performedAt,
            lines: lines
        )
    }

    /// The most recent finished session of this workout, excluding one.
    ///
    /// The exclusion is the session being trained right now: it is created
    /// before its first set is logged, so without this the hint would come
    /// from today and read as "you have already done this".
    private func recentCompletedSessionIDs(
        workoutName: String,
        excluding: Int?,
        pageLimit: Int
    ) async throws -> [Int] {
        var page: Int?
        var visited: Set<Int> = []
        var found: [(id: Int, at: Date)] = []

        repeat {
            let output = try await client.sessionsList(
                query: .init(page: page, status: .completed, workoutName: workoutName)
            )
            let response: Components.Schemas.PaginatedWorkoutSessionList
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
            for session in response.results {
                guard session.id != excluding,
                      let at = session.endedAt ?? session.startedAt else { continue }
                found.append((session.id, at))
            }
            page = try nextPage(response.next, visited: &visited)
        } while page != nil && visited.count < pageLimit

        return found.sorted { $0.at > $1.at }.map(\.id)
    }

    private func fetchSetEntries(
        session: Int
    ) async throws -> [Components.Schemas.SetEntry] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [Components.Schemas.SetEntry] = []
        repeat {
            let output = try await client.setEntriesList(
                query: .init(page: page, session: session)
            )
            let response: Components.Schemas.PaginatedSetEntryList
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


    /// The exercises belonging to one session.
    ///
    /// Narrowed by the server. The whole table used to come down so the caller
    /// could pick out one session's rows, which is work the database does in an
    /// indexed lookup and which grew with the account's entire history.
    private func fetchSessionExercises(
        session: Int
    ) async throws -> [Components.Schemas.SessionExercise] {
        var page: Int?
        var visited: Set<Int> = []
        var values: [Components.Schemas.SessionExercise] = []
        repeat {
            let output = try await client.sessionExercisesList(
                query: .init(page: page, session: session)
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
