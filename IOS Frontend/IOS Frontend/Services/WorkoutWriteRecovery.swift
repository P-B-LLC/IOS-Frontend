import Foundation

/// The receipt stays until its local consumer is durable (session start), or
/// until an explicit delete (set logging). A successful HTTP reply alone is not
/// a safe point to forget an operation: the process can die before updating UI.
@MainActor
enum WorkoutWriteRecovery {
    static func finishConsumption(key: String, contextKey: String, scope: EditorDraftRecovery.Scope,
                                  storage: EditorDraftRecovery = .shared) throws {
        guard try storage.load(Int.self, key: key + "-consumed", scope: scope) != nil else { return }
        try storage.remove(key: contextKey, scope: scope)
        try storage.remove(key: key, scope: scope)
        try storage.remove(key: key + "-consumed", scope: scope)
    }

    static func consume(key: String, contextKey: String, resourceID: Int, scope: EditorDraftRecovery.Scope,
                        storage: EditorDraftRecovery = .shared) throws {
        try storage.save(resourceID, key: key + "-consumed", scope: scope)
        try finishConsumption(key: key, contextKey: contextKey, scope: scope, storage: storage)
    }

    struct Receipt<Payload: Codable & Sendable>: Codable, Sendable {
        let operationID: UUID
        let payload: Payload
        var resourceID: Int?
    }

    static func create<Payload: Codable & Sendable>(
        key: String, payload: Payload, scope: EditorDraftRecovery.Scope,
        storage: EditorDraftRecovery = .shared,
        delete: @escaping @MainActor (Int) async throws -> Void,
        send: @escaping @MainActor (UUID, Payload) async throws -> Int
    ) async throws -> Receipt<Payload> {
        // Complete an interrupted unlog before accepting a genuinely new log.
        if let deleting = try storage.load(Int.self, key: key + "-delete", scope: scope) {
            try await remove(key: key, resourceID: deleting, scope: scope, storage: storage, send: delete)
        }
        var receipt = try storage.capture(Receipt(operationID: UUID(), payload: payload, resourceID: nil),
                                          key: key, scope: scope)
        if receipt.resourceID == nil {
            do {
                receipt.resourceID = try await send(receipt.operationID, receipt.payload)
            } catch APIServiceError.undocumentedStatus(400) {
                // Definitive validation rejection: no create was committed.
                try storage.remove(key: key, scope: scope)
                throw APIServiceError.undocumentedStatus(400)
            }
            try storage.save(receipt, key: key, scope: scope)
        }
        return receipt
    }

    static func remove(key: String, resourceID: Int, scope: EditorDraftRecovery.Scope,
                       storage: EditorDraftRecovery = .shared,
                       send: @escaping @MainActor (Int) async throws -> Void) async throws {
        // Tombstone first. A lost DELETE reply must not resurrect an old receipt.
        try storage.save(resourceID, key: key + "-delete", scope: scope)
        try await send(resourceID)
        try storage.remove(key: key, scope: scope)
        try storage.remove(key: key + "-delete", scope: scope)
    }
}
