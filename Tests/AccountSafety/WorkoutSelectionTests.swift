import Foundation
import HTTPTypes
import OpenAPIRuntime
import RepbaseAPI
import XCTest
@testable import AccountSafety

private actor WorkoutCreateTransport: ClientTransport {
    struct Request: Sendable {
        let method: HTTPRequest.Method
        let path: String?
        let key: String?
        let body: Data
    }

    let status: Int
    let responseBody: String
    private(set) var requests: [Request] = []

    init(status: Int = 201, responseBody: String = #"{"id":91,"owner":7,"name":"Leg Day","workout_type":"lifting","exercises":[],"created_at":"2026-10-28T12:00:00Z","updated_at":"2026-10-28T12:00:00Z"}"#) {
        self.status = status
        self.responseBody = responseBody
    }

    func send(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let data: Data
        if let body { data = try await Data(collecting: body, upTo: 1_048_576) }
        else { data = Data() }
        requests.append(.init(method: request.method, path: request.path,
                              key: request.headerFields[.init("Idempotency-Key")!], body: data))
        var response = HTTPResponse(status: .init(code: status))
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(Data(responseBody.utf8)))
    }
}

final class WorkoutSelectionTests: XCTestCase {
    private struct ScheduledWorkout: Identifiable {
        let id: UUID
        let templateID: Int
        let name: String
    }

    private func client(_ transport: WorkoutCreateTransport) -> Client {
        Client(serverURL: URL(string: "https://test.invalid")!, transport: transport)
    }

    private func appSource(_ path: String) throws -> String {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        return try String(contentsOf: URL(fileURLWithPath: root)
            .appendingPathComponent("IOS Frontend/IOS Frontend/\(path)"), encoding: .utf8)
            .replacingOccurrences(of: "\r\n", with: "\n")
    }

    private func section(_ source: String, from start: String, to end: String) throws -> String {
        let beginning = try XCTUnwrap(source.range(of: start))
        let ending = try XCTUnwrap(source.range(of: end, range: beginning.upperBound..<source.endIndex))
        return String(source[beginning.lowerBound..<ending.lowerBound])
    }

    func testCustomSelectionPostsExactCatalogIDsInOrderInsteadOfPremadeLegDay() async throws {
        let premadeIDs = [10, 11, 12]
        let selectedIDs = [53, 21, 53] // Repeated movement is still two planned rows.
        let selections: [WorkoutTemplateCreation.Selection] = [
            .init(exerciseID: 53, targetSets: 4),
            .init(exerciseID: 21, targetSets: nil),
            .init(exerciseID: 53, targetSets: 0)
        ]
        let plan = WorkoutTemplateCreation.initialExercises(selections)
        XCTAssertEqual(plan.map(\.exercise), selectedIDs)
        XCTAssertEqual(plan.map(\.order), [1, 2, 3])
        XCTAssertEqual(plan.map(\.targetSets), [4, nil, 0])

        let request = Components.Schemas.WorkoutTemplateRequest(
            name: "Leg Day", workoutType: .lifting, initialExercises: plan, initialDate: "2026-10-28"
        )
        let transport = WorkoutCreateTransport()
        let key = UUID()
        let created = try await WorkoutTemplateCreation.send(request, operationID: key, using: client(transport))
        XCTAssertEqual(created.id, 91)
        let sent = await transport.requests
        XCTAssertEqual(sent.count, 1)
        let first = try XCTUnwrap(sent.first)
        XCTAssertEqual(first.method, .post)
        XCTAssertEqual(first.path, "/api/v1/workouts/")
        XCTAssertEqual(first.key, key.uuidString)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: first.body) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "Leg Day")
        XCTAssertEqual(json["initial_date"] as? String, "2026-10-28")
        let rows = try XCTUnwrap(json["initial_exercises"] as? [[String: Any]])
        XCTAssertEqual(rows.compactMap { $0["exercise"] as? Int }, selectedIDs)
        XCTAssertNotEqual(rows.compactMap { $0["exercise"] as? Int }, premadeIDs)
        XCTAssertEqual(rows.compactMap { $0["order"] as? Int }, [1, 2, 3])
        XCTAssertNil(json["owner"], "Ownership is derived by the server, not posted by the client")
    }

    func testSameNameRejectionNeverReturnsOrModifiesTheExistingTemplate() async throws {
        // The backend owns exact-name uniqueness. A rejection is not permission
        // to schedule or overwrite an older template with different exercises.
        let transport = WorkoutCreateTransport(status: 400, responseBody: "{}")
        let request = Components.Schemas.WorkoutTemplateRequest(
            name: "Leg Day", initialExercises: WorkoutTemplateCreation.initialExercises([
                .init(exerciseID: 53, targetSets: 3), .init(exerciseID: 21, targetSets: 4)
            ])
        )
        do {
            _ = try await WorkoutTemplateCreation.send(request, operationID: UUID(), using: client(transport))
            XCTFail("A duplicate-name failure must keep the selected draft open, never reuse an old template")
        } catch APIServiceError.undocumentedStatus(400) {}
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.method, .post)
        XCTAssertEqual(requests.first?.path, "/api/v1/workouts/")
        let data = try XCTUnwrap(requests.first?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try XCTUnwrap(json["initial_exercises"] as? [[String: Any]])
        XCTAssertEqual(rows.compactMap { $0["exercise"] as? Int }, [53, 21])
    }

    func testRetrySendsTheOriginalOperationAndPlan() async throws {
        let transport = WorkoutCreateTransport()
        let request = Components.Schemas.WorkoutTemplateRequest(
            name: "Custom Legs", initialExercises: WorkoutTemplateCreation.initialExercises([
                .init(exerciseID: 88, targetSets: 2), .init(exerciseID: 30, targetSets: 5)
            ]), initialDate: "2026-10-28"
        )
        let key = UUID()
        _ = try await WorkoutTemplateCreation.send(request, operationID: key, using: client(transport))
        _ = try await WorkoutTemplateCreation.send(request, operationID: key, using: client(transport))
        let sent = await transport.requests
        XCTAssertEqual(sent.map(\.key), [key.uuidString, key.uuidString])
        let first = try JSONSerialization.jsonObject(with: sent[0].body) as? NSDictionary
        let retry = try JSONSerialization.jsonObject(with: sent[1].body) as? NSDictionary
        XCTAssertEqual(first, retry)
    }

    func testStartingSecondSameNameCardUsesItsExactScheduleIdentity() {
        let first = ScheduledWorkout(id: UUID(), templateID: 12, name: "Leg Day")
        let chosen = ScheduledWorkout(id: UUID(), templateID: 91, name: "Leg Day")
        let resolved = WorkoutSelectionPolicy.resolve(requestedID: chosen.id, in: [first, chosen])
        XCTAssertEqual(resolved?.templateID, 91)
        XCTAssertEqual(WorkoutSelectionPolicy.resolve(requestedID: nil, in: [first, chosen])?.templateID, 12)
        XCTAssertNil(WorkoutSelectionPolicy.resolve(requestedID: UUID(), in: [first, chosen]),
                     "A stale requested ID must never fall back to the day's first workout")
    }

    func testSessionRowsMatchSelectedIDsInChosenOrderIncludingRepeatedMovements() {
        XCTAssertEqual(WorkoutSelectionPolicy.sessionRelationIndices(planned: [53, 21, 53], actual: [53, 21, 53]), [0, 1, 2])
        XCTAssertEqual(WorkoutSelectionPolicy.sessionRelationIndices(planned: [53, 21], actual: [21, 53]), [1, 0])
        XCTAssertEqual(WorkoutSelectionPolicy.sessionRelationIndices(planned: [53, 21, 53], actual: [99, 53, 21, 53]), [1, 2, 3])
        XCTAssertNil(WorkoutSelectionPolicy.sessionRelationIndices(planned: [53, 21], actual: [10, 11]))
        XCTAssertNil(WorkoutSelectionPolicy.sessionRelationIndices(planned: [53, 21, 53], actual: [53, 21]))
        XCTAssertNil(WorkoutSelectionPolicy.sessionRelationIndices(planned: [nil], actual: [53]))
    }

    func testSameNameCompletionAndUndoCannotClaimAnotherTemplateOrAnUnlinkedSession() {
        let completed = [(sessionID: 100, workoutID: 12 as Int?, name: "Leg Day"),
                         (sessionID: 101, workoutID: 91 as Int?, name: "Leg Day"),
                         (sessionID: 102, workoutID: nil as Int?, name: "Leg Day")]
        let selectedIDs = completed.filter {
            WorkoutSelectionPolicy.sameTemplate(expected: 91, actual: $0.workoutID)
        }.map { $0.sessionID }
        XCTAssertEqual(selectedIDs, [101], "Only the chosen template can be completed or undone")
        XCTAssertFalse(WorkoutSelectionPolicy.sameTemplate(expected: nil, actual: nil))
        XCTAssertFalse(WorkoutSelectionPolicy.sameTemplate(expected: 91, actual: nil))
    }

    func testRepositoryUsesCreateOnlyPathAndDoesNotResolveTemplatesByName() throws {
        let repository = try appSource("API/WorkoutAPIRepository.swift")
        let create = try section(repository, from: "func createTemplate(", to: "func acknowledgeTemplateSave(")
        XCTAssertFalse(create.contains("fetchAllWorkouts"))
        XCTAssertFalse(create.contains("normalizedName"))
        XCTAssertFalse(create.contains("scheduleWorkout("))
        XCTAssertTrue(create.contains("WorkoutTemplateCreation.initialExercises(selections)"))
        XCTAssertTrue(create.contains("WorkoutTemplateCreation.send("))
        let resolve = try section(repository, from: "private func resolveExercise(", to: "private func findExercise(")
        XCTAssertTrue(resolve.contains("if let serverID = draft.serverID"))
        XCTAssertTrue(resolve.contains("return serverID"))
        let start = try section(repository, from: "func startSession(", to: "func recoverPendingSessionStart(")
        XCTAssertTrue(start.contains("actual: started.workout"))
        XCTAssertTrue(start.contains("sessionRelations.allSatisfy({ $0.session == createdID })"))
        XCTAssertTrue(start.contains("WorkoutSelectionPolicy.sessionRelationIndices("))
        XCTAssertTrue(start.contains("zip(workout.exercises, relationIndices)"))
    }

    func testSaveSuccessRequiresAuthoritativeTemplateAndDateBeforeAcknowledgingDraft() throws {
        let store = try appSource("Stores/WorkoutStore.swift")
        let save = try section(store, from: "func saveWorkout(_ workout:", to: "func removeWorkout(")
        let written = try XCTUnwrap(save.range(of: "let templateID = try await repository.saveWorkout("))
        let reloaded = try XCTUnwrap(save.range(of: "let reloaded = await reloadWeek("))
        let confirmed = try XCTUnwrap(save.range(of: "guard reloaded, let confirmed ="))
        let acknowledged = try XCTUnwrap(save.range(of: "try await repository.acknowledgeTemplateSave("))
        let selected = try XCTUnwrap(save.range(of: "lastSavedWorkoutID = confirmed.id"))
        XCTAssertLessThan(written.lowerBound, reloaded.lowerBound)
        XCTAssertLessThan(reloaded.lowerBound, confirmed.lowerBound)
        XCTAssertLessThan(confirmed.lowerBound, acknowledged.lowerBound)
        XCTAssertLessThan(acknowledged.lowerBound, selected.lowerBound)
        XCTAssertTrue(save.contains("$0.serverID == templateID && $0.scheduledDate == date"))
        let start = try section(store, from: "func startSession(on day:", to: "func updateSessionSet(")
        XCTAssertTrue(start.contains("WorkoutSelectionPolicy.resolve(requestedID: workoutID"))
        XCTAssertFalse(start.contains("?? workout(on: day)"))
    }

    func testCompletionAndUndoWireCanonicalSessionTemplateID() throws {
        let repository = try appSource("API/WorkoutAPIRepository.swift")
        XCTAssertTrue(repository.contains("workoutServerID: session.workout"))
        let store = try appSource("Stores/WorkoutStore.swift")
        let completed = try section(store, from: "func finishedSessions(workout: Workout", to: "func isCompleted(workout: Workout")
        XCTAssertTrue(completed.contains("expected: workout.serverID, actual: $0.workoutServerID"))
        XCTAssertFalse(completed.contains("workoutName"))
        let undo = try section(store, from: "func undoCompletion(workout: Workout", to: "private func undoCompletion(sessions")
        XCTAssertTrue(undo.contains("finishedSessions(workout: workout, on: date)"))
        XCTAssertFalse(undo.contains("workoutName"))
    }
}
