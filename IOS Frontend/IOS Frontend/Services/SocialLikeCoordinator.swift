import Foundation
import Observation

/// A single confirmed write per original post, shared by every visible copy.
/// No optimistic rollback can overwrite another tap. Reset invalidates late
/// success AND failure callbacks when the signed-in account changes.
@MainActor
@Observable
final class SocialLikeCoordinator {
    struct Confirmation: Equatable, Sendable {
        let liked: Bool
        let count: Int
    }

    private var requests: [Int: UUID] = [:]
    private var epoch = UUID()

    func isPending(_ postID: Int) -> Bool { requests[postID] != nil }

    func reset() {
        epoch = UUID()
        requests = [:]
    }

    func submit(
        postID: Int,
        operation: @MainActor () async throws -> Confirmation
    ) async throws -> Confirmation? {
        guard !isPending(postID) else { return nil }
        let request = UUID(), startedEpoch = epoch
        requests[postID] = request
        defer {
            if epoch == startedEpoch, requests[postID] == request {
                requests[postID] = nil
            }
        }
        do {
            let result = try await operation()
            guard epoch == startedEpoch, requests[postID] == request else { return nil }
            return result
        } catch {
            guard epoch == startedEpoch, requests[postID] == request else { return nil }
            throw error
        }
    }
}
