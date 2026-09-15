import Foundation

/// Orders reads against local writes without serializing unrelated days.
/// Request IDs also prevent an old completion from releasing a newer request.
@MainActor
final class FoodDaySyncCoordinator {
    struct Read {
        fileprivate let epoch: UUID
        fileprivate let id: UUID
        fileprivate let resource: String
        fileprivate let sequence: UInt64
        fileprivate let revision: UInt64
        fileprivate let writing: Set<String>
    }

    struct Write {
        fileprivate let epoch: UUID
        fileprivate let id: UUID
        let days: Set<String>
    }

    private var epoch = UUID()
    private var sequence: UInt64 = 0
    private var revision: UInt64 = 0
    private var reads: [String: UUID] = [:]
    private var writes: [String: UUID] = [:]
    private var ensures: [String: UUID] = [:]
    private var dayRevisions: [String: UInt64] = [:]
    private var acceptedReads: [String: UInt64] = [:]

    func reset() {
        epoch = UUID()
        sequence = 0
        revision = 0
        reads = [:]
        writes = [:]
        ensures = [:]
        dayRevisions = [:]
        acceptedReads = [:]
    }

    func beginRead(_ resource: String) -> Read? {
        guard reads[resource] == nil else { return nil }
        sequence += 1
        let id = UUID()
        reads[resource] = id
        return Read(epoch: epoch, id: id, resource: resource, sequence: sequence,
                    revision: revision, writing: Set(writes.keys))
    }

    func isCurrent(_ read: Read) -> Bool {
        read.epoch == epoch && reads[read.resource] == read.id
    }

    /// ensure-day is a POST that can create slots, not a snapshot-only GET.
    /// Range reads may update other dates but must not supersede this operation.
    func beginEnsureDay(_ day: String) -> Read? {
        guard !isWriting(day), let read = beginRead("day:\(day)") else { return nil }
        ensures[day] = read.id
        return read
    }

    @discardableResult
    func endRead(_ read: Read) -> Bool {
        guard isCurrent(read) else { return false }
        reads[read.resource] = nil
        if let day = ensures.first(where: { $0.value == read.id })?.key {
            ensures[day] = nil
            revision += 1
            dayRevisions[day] = revision
        }
        return true
    }

    var hasMonthReads: Bool { reads.keys.contains { $0.hasPrefix("month:") } }
    func isWriting(_ day: String) -> Bool { writes[day] != nil }

    /// Call only when actually applying a response, once for each returned day.
    /// A month can accept untouched days while rejecting one changed by a save.
    func accept(_ read: Read, day: String) -> Bool {
        guard isCurrent(read), !isWriting(day), !read.writing.contains(day),
              ensures[day] == nil || ensures[day] == read.id,
              (dayRevisions[day] ?? 0) <= read.revision,
              (acceptedReads[day] ?? 0) <= read.sequence else { return false }
        acceptedReads[day] = read.sequence
        return true
    }

    func beginWrite(days: Set<String>) -> Write {
        revision += 1
        let id = UUID()
        for day in days {
            writes[day] = id
            dayRevisions[day] = revision
            // A post-save refresh must not join a pre-save ensure-day request.
            reads["day:\(day)"] = nil
            ensures[day] = nil
        }
        return Write(epoch: epoch, id: id, days: days)
    }

    @discardableResult
    func endWrite(_ write: Write) -> Bool {
        guard write.epoch == epoch,
              write.days.allSatisfy({ writes[$0] == write.id }) else { return false }
        revision += 1
        for day in write.days {
            writes[day] = nil
            // Also reject reads started during a write that ultimately failed.
            dayRevisions[day] = revision
        }
        return true
    }
}
