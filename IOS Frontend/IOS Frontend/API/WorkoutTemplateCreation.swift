import Foundation
import RepbaseAPI

/// The create-only API path. Reusing a saved template is a separate explicit
/// schedule operation, never a lookup by the new draft's display name.
nonisolated enum WorkoutTemplateCreation {
    static func recoveryKey(for draftID: UUID) -> String {
        "create-workout-\(draftID)"
    }

    @MainActor static func hasPendingSave(draftID: UUID) -> Bool {
        let recovery = EditorDraftRecovery.shared
        guard let scope = recovery.scope else { return false }
        return recovery.contains(key: recoveryKey(for: draftID), scope: scope)
    }

    struct Selection: Sendable {
        let exerciseID: Int
        let targetSets: Int?
        var targetReps: Int? = nil
        var targetWeightKilograms: String? = nil
        var restSeconds: Int? = nil
        var supersetGroup: Int? = nil
        /// Raw API values, so this file needs no app model to compile alone.
        var setTypes: [Components.Schemas.SetTypeEnum] = []
        var plannedSets: [Components.Schemas.WorkoutPlannedSetRequest]? = nil
    }

    static func initialExercises(_ selections: [Selection]) -> [Components.Schemas.InitialWorkoutExerciseRequest] {
        selections.enumerated().map { index, selection in
            .init(exercise: selection.exerciseID, order: Int64(index + 1),
                  targetSets: selection.targetSets.map(Int64.init),
                  targetReps: selection.targetReps.map(Int64.init),
                  targetWeightKg: selection.targetWeightKilograms,
                  restSeconds: selection.restSeconds,
                  supersetGroup: selection.supersetGroup,
                  // Left out rather than sent empty when there are none, so
                  // the request reads the same as one from before set kinds.
                  setTypes: selection.setTypes.isEmpty ? nil : selection.setTypes,
                  plannedSets: selection.plannedSets)
        }
    }

    static func send(
        _ request: Components.Schemas.WorkoutTemplateRequest,
        operationID: UUID,
        using client: Client
    ) async throws -> Components.Schemas.WorkoutTemplate {
        let output = try await client.workoutsCreate(
            headers: .init(idempotencyKey: operationID.uuidString), body: .json(request)
        )
        switch output {
        case .created(let response): return try response.body.json
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(
                statusCode: statusCode, payload: payload, unlabeled: ["name"]
            )
        }
    }
}
