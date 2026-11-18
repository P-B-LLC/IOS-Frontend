import Foundation
import XCTest
@testable import AccountSafety

final class EditorDraftRecoveryTests: XCTestCase {
    @MainActor func testPendingWriteDetectionSurvivesRelaunchAndRespectsAccountAndOrigin() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let scope = EditorDraftRecovery.Scope(ownerID: 5, origin: "https://one.invalid")
        let otherAccount = EditorDraftRecovery.Scope(ownerID: 6, origin: scope.origin)
        let otherOrigin = EditorDraftRecovery.Scope(ownerID: 5, origin: "https://two.invalid")
        let key = WorkoutTemplateCreation.recoveryKey(for: UUID())
        let storage = EditorDraftRecovery(directory: directory, defaults: defaults)
        XCTAssertFalse(storage.contains(key: key, scope: scope))
        try storage.save(["name": "Push Day"], key: key, scope: scope)
        let reopened = EditorDraftRecovery(directory: directory, defaults: defaults)
        XCTAssertTrue(reopened.contains(key: key, scope: scope))
        XCTAssertFalse(reopened.contains(key: key, scope: otherAccount))
        XCTAssertFalse(reopened.contains(key: key, scope: otherOrigin))
        try reopened.remove(key: key, scope: scope)
        XCTAssertFalse(storage.contains(key: key, scope: scope))
        try storage.save(["name": "Push Day"], key: key, scope: scope)
        try reopened.removeAccount(scope: scope)
        XCTAssertFalse(storage.contains(key: key, scope: scope))
    }

    @MainActor func testCorruptPendingRequestCannotBeReplacedByANewPayload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = EditorDraftRecovery(directory: directory, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let scope = EditorDraftRecovery.Scope(ownerID: 1, origin: "https://one.invalid")
        try storage.save(["name": "Original"], key: "pending", scope: scope)
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)!
        let file = try XCTUnwrap(files.allObjects.compactMap { $0 as? URL }.first { $0.pathExtension == "json" })
        let corrupt = Data("interrupted or unreadable data".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try storage.capture(["name": "Changed"], key: "pending", scope: scope))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    @MainActor func testLostResponseKeepsOriginalRequestDespiteEditedDraftAndRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let scope = EditorDraftRecovery.Scope(ownerID: 5, origin: "https://one.invalid")
        let storage = EditorDraftRecovery(directory: directory, defaults: defaults)
        let original = ["name": "Original", "operation": UUID().uuidString]
        XCTAssertEqual(try storage.capture(original, key: "pending-create", scope: scope), original)
        // Simulate the process dying after the server writes but before its response.
        let reopened = EditorDraftRecovery(directory: directory, defaults: defaults)
        let changed = ["name": "Edited", "operation": original["operation"]!]
        XCTAssertEqual(try reopened.capture(changed, key: "pending-create", scope: scope), original)
        try reopened.remove(key: "pending-create", scope: scope)
        XCTAssertNil(try storage.load([String: String].self, key: "pending-create", scope: scope))
    }

    @MainActor func testRelaunchIsolationAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = EditorDraftRecovery.Scope(ownerID: 1, origin: "https://one.invalid")
        let other = EditorDraftRecovery.Scope(ownerID: 2, origin: first.origin)
        let storage = EditorDraftRecovery(directory: directory, defaults: defaults)
        try storage.save(["name": "Lunch", "id": "stable-save-id"], key: "food", scope: first)
        let reopened = EditorDraftRecovery(directory: directory, defaults: defaults)
        XCTAssertEqual(try reopened.load([String: String].self, key: "food", scope: first)?["id"], "stable-save-id")
        XCTAssertNil(try reopened.load([String: String].self, key: "food", scope: other))
        let otherBackend = EditorDraftRecovery.Scope(ownerID: first.ownerID, origin: "https://two.invalid")
        XCTAssertNil(try reopened.load([String: String].self, key: "food", scope: otherBackend))
        try reopened.removeAccount(scope: first)
        XCTAssertNil(try storage.load([String: String].self, key: "food", scope: first))
        XCTAssertThrowsError(try storage.save(["name": "Late response"], key: "food", scope: first))
    }
}
