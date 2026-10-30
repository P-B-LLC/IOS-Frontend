import Foundation

/// Names are labels, not identities. Never substitute another workout when a
/// caller asks for a particular scheduled row or saved template.
nonisolated enum WorkoutSelectionPolicy {
    static func resolve<Item: Identifiable>(requestedID: Item.ID?, in items: [Item]) -> Item? {
        guard let requestedID else { return items.first }
        return items.first { $0.id == requestedID }
    }

    static func sameTemplate(expected: Int?, actual: Int?) -> Bool {
        guard let expected else { return false }
        return expected == actual
    }

    /// Resolve rows one-to-one by catalog ID, retaining the chosen plan's order.
    /// Repeated movements consume distinct session rows. A server ordering
    /// difference alone must not strand an otherwise recoverable session.
    static func sessionRelationIndices(planned: [Int?], actual: [Int]) -> [Int]? {
        var remaining = Array(actual.enumerated())
        var indices: [Int] = []
        for exerciseID in planned {
            guard let exerciseID,
                  let index = remaining.firstIndex(where: { $0.element == exerciseID }) else { return nil }
            indices.append(remaining.remove(at: index).offset)
        }
        return indices
    }
}
