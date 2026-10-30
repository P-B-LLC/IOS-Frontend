import Foundation
import RepbaseAPI

/// The create-only API path. Reusing a saved template is a separate explicit
/// schedule operation, never a lookup by the new draft's display name.
nonisolated enum WorkoutTemplateCreation {
    struct Selection: Sendable {
        let exerciseID: Int
        let targetSets: Int?
        var targetReps: Int? = nil
        var targetWeightKilograms: String? = nil
        var restSeconds: Int? = nil
        var supersetGroup: Int? = nil
        /// Raw API values, so this file needs no app model to compile alone.
        var setTypes: [Components.Schemas.SetTypeEnum] = []
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
                  setTypes: selection.setTypes.isEmpty ? nil : selection.setTypes)
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
        case .undocumented(let statusCode, _): throw APIServiceError.undocumentedStatus(statusCode)
        }
    }
}
