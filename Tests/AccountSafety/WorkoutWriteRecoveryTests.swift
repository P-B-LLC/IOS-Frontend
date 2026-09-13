import Foundation
import XCTest
@testable import AccountSafety

final class WorkoutWriteRecoveryTests: XCTestCase {
    @MainActor private func storage() -> (EditorDraftRecovery, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (EditorDraftRecovery(directory: directory, defaults: UserDefaults(suiteName: UUID().uuidString)!), directory)
    }
    private let scope = EditorDraftRecovery.Scope(ownerID: 7, origin: "https://test.invalid")

    @MainActor func testLostCreateReplyReusesOriginalKeyAndPayloadAcrossRelaunch() async throws {
        let (disk, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        var rows: [UUID: [String: String]] = [:]
        var requests: [UUID] = []
        let original = ["reps": "8", "completed_at": "original-time"]
        do {
            _ = try await WorkoutWriteRecovery.create(key: "set", payload: original, scope: scope, storage: disk,
                delete: { _ in XCTFail() }, send: { key, payload in
                    requests.append(key); rows[key] = payload
                    throw URLError(.networkConnectionLost) // committed, reply lost
                })
            XCTFail("Expected a lost response")
        } catch is URLError {}
        let reopened = EditorDraftRecovery(directory: directory, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let receipt = try await WorkoutWriteRecovery.create(key: "set", payload: ["reps": "12"], scope: scope, storage: reopened,
            delete: { _ in XCTFail() }, send: { key, payload in
                requests.append(key)
                XCTAssertEqual(rows[key], payload)
                return 81
            })
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(Set(requests).count, 1)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(receipt.payload, original)
        XCTAssertEqual(receipt.resourceID, 81)
        // A crash after receipt persistence but before the UI update needs no POST.
        let again = try await WorkoutWriteRecovery.create(key: "set", payload: original, scope: scope, storage: reopened,
            delete: { _ in XCTFail() }, send: { _, _ in XCTFail("Duplicate network request"); return 0 })
        XCTAssertEqual(again.resourceID, 81)
    }

    @MainActor func testUnlogLostReplyThenRelogUsesANewOperation() async throws {
        let (disk, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        var exists = true
        let first = try await WorkoutWriteRecovery.create(key: "set", payload: ["reps": "8"], scope: scope, storage: disk,
            delete: { _ in XCTFail() }, send: { _, _ in 10 })
        do {
            try await WorkoutWriteRecovery.remove(key: "set", resourceID: 10, scope: scope, storage: disk,
                send: { _ in exists = false; throw URLError(.timedOut) })
            XCTFail("Expected lost DELETE response")
        } catch is URLError {}
        let next = try await WorkoutWriteRecovery.create(key: "set", payload: ["reps": "12"], scope: scope, storage: disk,
            delete: { id in XCTAssertEqual(id, 10); XCTAssertFalse(exists) /* already gone is success */ },
            send: { _, payload in XCTAssertEqual(payload["reps"], "12"); return 11 })
        XCTAssertNotEqual(first.operationID, next.operationID)
        XCTAssertEqual(next.resourceID, 11)
        XCTAssertNil(try disk.load(Int.self, key: "set-delete", scope: scope))
    }

    @MainActor func testValidationFailureCanBeCorrectedWithoutKeepingBadPayload() async throws {
        let (disk, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        var rejectedKey: UUID?
        do {
            _ = try await WorkoutWriteRecovery.create(key: "set", payload: ["reps": "bad"], scope: scope, storage: disk,
                delete: { _ in XCTFail() }, send: { id, _ in rejectedKey = id; throw APIServiceError.undocumentedStatus(400) })
            XCTFail()
        } catch APIServiceError.undocumentedStatus(400) {}
        let fixed = try await WorkoutWriteRecovery.create(key: "set", payload: ["reps": "8"], scope: scope, storage: disk,
            delete: { _ in XCTFail() }, send: { id, value in
                XCTAssertNotEqual(id, rejectedKey); XCTAssertEqual(value["reps"], "8"); return 2
            })
        XCTAssertEqual(fixed.resourceID, 2)
    }

    @MainActor func testInterruptedStartConsumptionCannotReplayTheOldSession() async throws {
        let (disk, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await WorkoutWriteRecovery.create(key: "start", payload: ["workout": 1], scope: scope, storage: disk,
            delete: { _ in XCTFail() }, send: { _, _ in 19 })
        try disk.save(["workout": 1], key: "context", scope: scope)
        // Crash after durable checkpoint/consumed marker but before both removals.
        try disk.save(19, key: "start-consumed", scope: scope)
        try disk.remove(key: "context", scope: scope)
        try WorkoutWriteRecovery.finishConsumption(key: "start", contextKey: "context", scope: scope, storage: disk)
        let next = try await WorkoutWriteRecovery.create(key: "start", payload: ["workout": 2], scope: scope, storage: disk,
            delete: { _ in XCTFail() }, send: { _, payload in XCTAssertEqual(payload["workout"], 2); return 20 })
        XCTAssertNotEqual(first.operationID, next.operationID)
        XCTAssertEqual(next.resourceID, 20)
    }

    @MainActor func testDeletionDuringResponseCannotRecreateRecoveryData() async throws {
        let (disk, directory) = storage()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await WorkoutWriteRecovery.create(key: "set", payload: ["reps": 8], scope: scope, storage: disk,
                delete: { _ in XCTFail() }, send: { [scope] _, _ in
                    try disk.removeAccount(scope: scope)
                    return 10
                })
            XCTFail("Deleted account must reject late receipt writes")
        } catch {}
        XCTAssertNil(try disk.load(WorkoutWriteRecovery.Receipt<[String: Int]>.self, key: "set", scope: scope))
    }
}
