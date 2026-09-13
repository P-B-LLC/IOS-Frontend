import Foundation

nonisolated struct PendingWorkoutSave: Codable, Identifiable, Sendable {
    let id: UUID
    let ownerID: Int
    let origin: String
    let sessionID: Int
    let workoutName: String
    let requestedAt: Date
    let points: [RoutePoint]
}

/// A durable finish intent, written before any upload. No credentials are stored.
/// Entries are isolated by account AND backend; logout hides but does not erase
/// unsynced work. Account deletion explicitly removes that account's entries.
@MainActor
final class PendingWorkoutSaves {
    private let directory: URL
    private let defaults: UserDefaults
    private let deletedAccountsKey = "workoutRecovery.deletedAccounts"
    private let discardedSessionsKey = "workoutRecovery.discardedSessions"
    private var file: URL { directory.appendingPathComponent("pending-workouts.json") }

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkoutRecovery", isDirectory: true)
    }

    func entries(ownerID: Int, origin: String) throws -> [PendingWorkoutSave] {
        try all().filter { $0.ownerID == ownerID && $0.origin == origin }
    }

    func put(_ entry: PendingWorkoutSave) throws {
        var entries = try all()
        entries.removeAll { $0.ownerID == entry.ownerID && $0.origin == entry.origin && $0.sessionID == entry.sessionID }
        entries.append(entry)
        try write(entries)
    }

    func remove(_ entry: PendingWorkoutSave) throws {
        try write(all().filter { $0.id != entry.id })
    }

    func removeAccount(ownerID: Int, origin: String) throws {
        var deleted = Set(defaults.stringArray(forKey: deletedAccountsKey) ?? [])
        deleted.insert("\(ownerID)|\(origin)")
        defaults.set(Array(deleted), forKey: deletedAccountsKey)
        try write(all().filter { $0.ownerID != ownerID || $0.origin != origin })
    }

    /// Record confirmed server deletion before attempting file cleanup, so a
    /// cleanup failure cannot send a discarded session on the next launch.
    func discardSession(ownerID: Int, origin: String, sessionID: Int) throws {
        var discarded = Set(defaults.stringArray(forKey: discardedSessionsKey) ?? [])
        discarded.insert("\(ownerID)|\(origin)|\(sessionID)")
        defaults.set(Array(discarded), forKey: discardedSessionsKey)
        try write(all())
    }

    private func all() throws -> [PendingWorkoutSave] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        // Never silently replace unreadable/corrupt recovery data with an empty list.
        let entries = try JSONDecoder().decode([PendingWorkoutSave].self, from: Data(contentsOf: file))
        let deleted = Set(defaults.stringArray(forKey: deletedAccountsKey) ?? [])
        let discarded = Set(defaults.stringArray(forKey: discardedSessionsKey) ?? [])
        let retained = entries.filter {
            !deleted.contains("\($0.ownerID)|\($0.origin)") &&
            !discarded.contains("\($0.ownerID)|\($0.origin)|\($0.sessionID)")
        }
        if retained.count != entries.count { try write(retained) }
        return retained
    }

    private func write(_ entries: [PendingWorkoutSave]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var protectedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(values)
        var options: Data.WritingOptions = [.atomic]
#if os(iOS)
        options.insert(.completeFileProtectionUnlessOpen)
#endif
        try JSONEncoder().encode(entries).write(to: file, options: options)
    }
}
