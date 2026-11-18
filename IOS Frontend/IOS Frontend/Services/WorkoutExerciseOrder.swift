import Foundation

/// Repositions complete planned rows without rebuilding their identity or
/// changing set kinds, targets, rests or superset membership. Destination uses
/// List.onMove's pre-removal insertion offset, including the end of the list.
nonisolated enum WorkoutExerciseOrder {
    static func moving(
        _ exercises: [Exercise], fromOffsets source: IndexSet, toOffset destination: Int
    ) -> [Exercise] {
        guard !source.isEmpty, (0...exercises.count).contains(destination),
              source.allSatisfy({ exercises.indices.contains($0) }) else { return exercises }
        let moved = source.map { exercises[$0] }
        var remaining = exercises.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertion = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moved, at: insertion)
        return remaining
    }

    static func moving(_ id: UUID, by offset: Int, in exercises: [Exercise]) -> [Exercise] {
        guard let source = exercises.firstIndex(where: { $0.id == id }) else { return exercises }
        let (target, overflow) = source.addingReportingOverflow(offset)
        guard !overflow, exercises.indices.contains(target) else { return exercises }
        return moving(exercises, fromOffsets: IndexSet(integer: source),
                      toOffset: target + (target > source ? 1 : 0))
    }
}
