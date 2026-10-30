import Foundation

/// The shape of a workout -- which exercises, in what order, with what sets
/// and rests -- without any of the numbers lifted in it.
///
/// Taken from the saved workout when a session starts, so finishing can tell
/// whether today's session was trained to the plan or reshaped along the way.
/// Weights and reps are deliberately not part of it: changing those is what a
/// session is for, and asking about them after every workout would turn a
/// useful question into one people learn to dismiss.
nonisolated struct WorkoutStructure: Codable, Hashable, Sendable {
    nonisolated struct Item: Codable, Hashable, Sendable {
        /// The saved row this came from. Nil for an exercise added during the
        /// session, which is what marks it as new.
        let workoutExerciseID: Int?
        let exerciseServerID: Int?
        let name: String
        let setTypes: [WorkoutSetType]
        let restSeconds: Int?
        let supersetGroup: Int?
    }

    var items: [Item]
}

nonisolated enum WorkoutStructureChange: Hashable, Sendable {
    case added(String)
    case removed(String)
    case reordered
    case sets(String)
    case setTypes(String)
    case rest(String)
    case superset(String)
}

nonisolated enum WorkoutStructureDiff {
    /// Every way the session's shape differs from the plan's, in the order a
    /// summary should list them.
    static func changes(from plan: WorkoutStructure, to session: WorkoutStructure) -> [WorkoutStructureChange] {
        var changes: [WorkoutStructureChange] = []
        let planned = Dictionary(
            plan.items.compactMap { item in item.workoutExerciseID.map { ($0, item) } },
            uniquingKeysWith: { first, _ in first }
        )
        let kept = Set(session.items.compactMap(\.workoutExerciseID)).intersection(planned.keys)

        for item in session.items where item.workoutExerciseID.map({ planned[$0] == nil }) ?? true {
            changes.append(.added(item.name))
        }
        for item in plan.items where !(item.workoutExerciseID.map(kept.contains) ?? false) {
            changes.append(.removed(item.name))
        }

        // Order is compared among the exercises both still share, so adding
        // or removing one is not also reported as a reorder.
        let planOrder = plan.items.compactMap(\.workoutExerciseID).filter(kept.contains)
        let sessionOrder = session.items.compactMap(\.workoutExerciseID).filter(kept.contains)
        if planOrder != sessionOrder { changes.append(.reordered) }

        for item in session.items {
            guard let id = item.workoutExerciseID, let before = planned[id] else { continue }
            if item.setTypes.count != before.setTypes.count {
                changes.append(.sets(item.name))
            } else if item.setTypes != before.setTypes {
                changes.append(.setTypes(item.name))
            }
            if item.restSeconds != before.restSeconds { changes.append(.rest(item.name)) }
            // Compared by who an exercise is grouped with, not by the group's
            // number: numbers only mean "these belong together", and a group
            // renumbered after another was removed is still the same group.
            if partners(of: item, in: session) != partners(of: before, in: plan) {
                changes.append(.superset(item.name))
            }
        }
        return changes
    }

    private static func partners(of item: WorkoutStructure.Item, in structure: WorkoutStructure) -> Set<String> {
        guard let group = item.supersetGroup else { return [] }
        return Set(structure.items.filter { $0.supersetGroup == group && $0 != item }.map { partner in
            partner.workoutExerciseID.map { "saved-\($0)" } ?? "new-\(partner.name)"
        })
    }

    /// Superset numbers only mean "these belong together", so two plans that
    /// group the same exercises under different numbers are the same plan.
    /// Renumbering in order of first appearance gives a plan the small,
    /// stable numbers the backend stores.
    static func normalizedSupersets(_ groups: [Int?]) -> [Int?] {
        var mapping: [Int: Int] = [:]
        return groups.map { group in
            guard let group else { return nil }
            if let known = mapping[group] { return known }
            let next = mapping.count + 1
            mapping[group] = next
            return next
        }
    }

    /// The set kinds a plan stores: trailing normal sets are implied by the
    /// set count, so they are left off, the way the backend stores them.
    static func storedSetTypes(_ types: [WorkoutSetType]) -> [WorkoutSetType] {
        var trimmed = types
        while trimmed.last == .normal { trimmed.removeLast() }
        return trimmed
    }
}
