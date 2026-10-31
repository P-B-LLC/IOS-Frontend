import Foundation

/// A refresh started before a local write (or a newer refresh) cannot replace
/// the confirmed library. Account switches replace the store's gate entirely.
nonisolated struct CookbookSyncGate: Sendable {
    struct Read: Equatable, Sendable {
        fileprivate let revision: UInt64
        fileprivate let sequence: UInt64
    }
    private var revision: UInt64 = 0
    private var sequence: UInt64 = 0

    mutating func beginRead() -> Read {
        sequence &+= 1
        return Read(revision: revision, sequence: sequence)
    }

    mutating func wrote() { revision &+= 1 }

    func accepts(_ read: Read) -> Bool {
        read.revision == revision && read.sequence == sequence
    }
}
