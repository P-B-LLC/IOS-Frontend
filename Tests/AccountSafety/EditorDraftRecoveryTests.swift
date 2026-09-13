import Foundation
import XCTest
@testable import AccountSafety

final class EditorDraftRecoveryTests: XCTestCase {
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
