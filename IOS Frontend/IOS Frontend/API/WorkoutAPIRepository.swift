//
//  WorkoutAPIRepository.swift
//  IOS Frontend
//
//  OAS-generated workout, schedule, and session operations.
//

import Foundation
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

    func loadWeek(dateByDay: [Weekday: String]) async throws -> [Weekday: Workout] {
        async let schedulesRequest = fetchAllSchedules()
        async let workoutsRequest = fetchAllWorkouts()
        let (schedules, templates) = try await (schedulesRequest, workoutsRequest)

        let dayByDate = Dictionary(
            uniqueKeysWithValues: dateByDay.map { ($0.value, $0.key) }
        )
        let templateByID = Dictionary(
            uniqueKeysWithValues: templates.map { ($0.id, $0) }
        )

        var result: [Weekday: Workout] = [:]
        for schedule in schedules.sorted(by: { $0.id < $1.id }) {
            guard let day = dayByDate[schedule.scheduledDate],
                  result[day] == nil,
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

            result[day] = Workout(
                serverID: template.id,
                scheduleID: schedule.id,
                scheduledDate: schedule.scheduledDate,
                name: template.name,
                exercises: exercises
            )
        }
        return result
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
        let templateOutput = try await client.workoutsCreate(
            body: .json(
                Components.Schemas.WorkoutTemplateRequest(name: draft.name)
            )
        )

        let template: Components.Schemas.WorkoutTemplate
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
                            targetSets: Int64(exercise.sets)
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

            let scheduleOutput = try await client.schedulesCreate(
                body: .json(
                    Components.Schemas.WorkoutScheduleRequest(
                        workout: template.id,
                        scheduledDate: scheduledDate
                    )
                )
            )
            switch scheduleOutput {
            case .created:
                return
            case .undocumented(let statusCode, _):
                throw APIServiceError.undocumentedStatus(statusCode)
            }
        } catch {
            throw APIServiceError.partialWorkoutCreation(
                "The template exists on the server, but its exercises or date assignment need attention. \(error.localizedDescription)"
            )
        }
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
                    name: draft.name
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
                                targetSets: Int64(exercise.sets)
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
                                targetSets: Int64(exercise.sets)
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
                    sets: (1...max(exercise.sets, 1)).map {
                        WorkoutSetDraft(setNumber: $0)
                    }
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
            startedAt: started.startedAt ?? Date(),
            exercises: exercises
        )
    }

    func logSet(
        _ set: WorkoutSetDraft,
        sessionExerciseID: Int
    ) async throws -> Int {
        guard let reps = Int64(
            set.reps.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            throw APIServiceError.malformedResponse
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

    private static func safeSetCount(_ value: Int64?) -> Int {
        guard let value, value > 0, let count = Int(exactly: value) else {
            return 1
        }
        return min(count, 20)
    }
}
