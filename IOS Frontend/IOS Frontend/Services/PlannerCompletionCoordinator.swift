import Foundation
import Observation

/// One in-flight completion write per server task, shared by all its visible
/// copies. No optimistic state/rollback: only an accepted response changes state.
@Observable
@MainActor
final class PlannerCompletionCoordinator {
    struct ReadToken {
        fileprivate let epoch: UUID
        fileprivate let revision: UInt64
        fileprivate let pending: Set<Int>
    }

    private struct State {
        var confirmed: Bool
        var revision: UInt64
        var request: UUID?
    }

    private var states: [Int: State] = [:]
    private var epoch = UUID()
    private var revision: UInt64 = 0

    func isPending(_ serverID: Int) -> Bool { states[serverID]?.request != nil }

    func reset() {
        epoch = UUID()
        states = [:]
        revision = 0
    }

    func beginRead() -> ReadToken {
        ReadToken(epoch: epoch, revision: revision,
                  pending: Set(states.compactMap { $0.value.request == nil ? nil : $0.key }))
    }

    /// A GET started before/during a PATCH must not put yesterday's value back.
    /// A subsequent clean read is authoritative, including changes on other devices.
    func reconcile(_ value: Bool, serverID: Int, read: ReadToken) -> Bool {
        guard read.epoch == epoch, let state = states[serverID] else { return value }
        if state.request != nil || state.revision > read.revision || read.pending.contains(serverID) {
            return state.confirmed
        }
        return value
    }

    @discardableResult
    func submit(
        serverID: Int, current: Bool, desired: Bool,
        operation: @escaping @MainActor () async throws -> Bool,
        onSuccess: @escaping @MainActor (Bool) -> Void,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> Bool {
        guard !isPending(serverID), current != desired else { return false }
        let request = UUID()
        let requestEpoch = epoch
        revision += 1
        states[serverID] = State(confirmed: current, revision: revision, request: request)

        Task {
            do {
                let confirmed = try await operation()
                guard epoch == requestEpoch, states[serverID]?.request == request else { return }
                revision += 1
                states[serverID] = State(confirmed: confirmed, revision: revision, request: nil)
                onSuccess(confirmed)
            } catch {
                guard epoch == requestEpoch, states[serverID]?.request == request else { return }
                revision += 1
                states[serverID] = State(confirmed: current, revision: revision, request: nil)
                onFailure(error)
            }
        }
        return true
    }
}
