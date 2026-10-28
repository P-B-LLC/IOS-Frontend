import Foundation

/// Calendar changes can arrive while another refresh is awaiting the server.
/// Keep one worker and coalesce those changes into a fresh pass, rather than
/// dropping them behind an `isRefreshing` guard or starting competing reads.
@MainActor
final class CalendarRefreshCoordinator {
    private var epoch = UUID()
    private var requested = UUID()
    private var latestOperation: (@MainActor () async -> Void)?
    private var worker: Task<Void, Never>?

    /// The operation must read current store state when it runs. Do not capture
    /// a schedule snapshot at the call site: a queued follow-up needs the newest
    /// confirmed schedule, including an empty one after clearing the calendar.
    func refresh(_ operation: @escaping @MainActor () async -> Void) async {
        requested = UUID()
        latestOperation = operation
        if worker == nil {
            let generation = epoch
            // An unstructured task is independent of a view task's cancellation.
            // A new notification must not cancel the refresh it is waiting for.
            worker = Task { [weak self] in
                guard let self else { return }
                await self.drain(generation: generation)
            }
        }
        let activeWorker = worker
        await activeWorker?.value
    }

    /// Account changes invalidate both queued work and old worker cleanup.
    /// Cancellation is cooperative: an old response may still arrive later.
    func reset() {
        epoch = UUID()
        requested = UUID()
        worker?.cancel()
        worker = nil
        latestOperation = nil
    }

    private func drain(generation: UUID) async {
        while epoch == generation, !Task.isCancelled {
            let servicing = requested
            guard let operation = latestOperation else { break }
            await operation()
            guard epoch == generation else { return }
            if requested == servicing { break }
        }
        guard epoch == generation else { return }
        worker = nil
        latestOperation = nil
    }
}

/// A fresh read or a confirmed mutation invalidates earlier server snapshots.
/// Apply the token to every collection populated by that read, not just the
/// visible month: overdue tasks and reminder candidates must agree with it.
@MainActor
final class CalendarReadGate {
    private var latest: UUID?

    func begin() -> UUID {
        let token = UUID()
        latest = token
        return token
    }

    func invalidate() { latest = nil }

    func accepts(_ token: UUID) -> Bool { latest == token }
}
