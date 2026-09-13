import CryptoKit
import Foundation

/// Account-scoped local drafts. No tokens are stored, and files are excluded
/// from backups. Explicit scopes prevent an old request touching a new account.
@MainActor
final class EditorDraftRecovery {
    static let shared = EditorDraftRecovery()
    struct Scope: Hashable, Sendable {
        let ownerID: Int
        let origin: String
    }
    var scope: Scope?
    private let directory: URL
    private let defaults: UserDefaults
    private let deletedKey = "editorRecovery.deletedAccounts"

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EditorRecovery", isDirectory: true)
    }

    func load<T: Decodable>(_ type: T.Type, key: String, scope: Scope) throws -> T? {
        guard !isDeleted(scope) else { return nil }
        let file = url(key: key, scope: scope)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: file))
    }

    func save<T: Encodable>(_ value: T, key: String, scope: Scope) throws {
        guard !isDeleted(scope) else { throw CocoaError(.fileWriteNoPermission) }
        let file = url(key: key, scope: scope)
        var folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var metadata = URLResourceValues()
        metadata.isExcludedFromBackup = true
        try folder.setResourceValues(metadata)
        var options: Data.WritingOptions = [.atomic]
#if os(iOS)
        options.insert(.completeFileProtectionUnlessOpen)
#endif
        try JSONEncoder().encode(value).write(to: file, options: options)
    }

    /// Keep the first submitted snapshot until its result is confirmed. Later
    /// edits must not change the payload associated with an idempotency key.
    func capture<T: Codable>(_ value: T, key: String, scope: Scope) throws -> T {
        if let existing = try load(T.self, key: key, scope: scope) { return existing }
        try save(value, key: key, scope: scope)
        return value
    }

    func remove(key: String, scope: Scope) throws {
        let file = url(key: key, scope: scope)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    func removeAccount(scope: Scope) throws {
        var deleted = Set(defaults.stringArray(forKey: deletedKey) ?? [])
        deleted.insert(hash("\(scope.ownerID)|\(scope.origin)"))
        defaults.set(Array(deleted), forKey: deletedKey)
        let folder = directory.appendingPathComponent(hash("\(scope.ownerID)|\(scope.origin)"), isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    private func url(key: String, scope: Scope) -> URL {
        directory.appendingPathComponent(hash("\(scope.ownerID)|\(scope.origin)"), isDirectory: true)
            .appendingPathComponent(hash(key) + ".json")
    }

    private func isDeleted(_ scope: Scope) -> Bool {
        (defaults.stringArray(forKey: deletedKey) ?? []).contains(hash("\(scope.ownerID)|\(scope.origin)"))
    }

    private func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
