import Foundation

/// Owns schedule writes independently of cancellable SwiftUI view tasks.
/// While one rebuild runs, only the latest requested snapshot is retained.
@MainActor
final class ReminderRebuildQueue {
    private var pending: (@MainActor () async -> Void)?
    private var worker: Task<Void, Never>?

    func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        pending = operation
        if let worker { return worker }
        let task = Task { @MainActor in
            while let operation = self.pending {
                self.pending = nil
                await operation()
            }
            self.worker = nil
        }
        worker = task
        return task
    }

    /// Account invalidation separately guards any already-running OS write.
    func discardPending() { pending = nil }
}
