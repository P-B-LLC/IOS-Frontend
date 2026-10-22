import Foundation

/// Chooses focus without modifying exercise order, inputs or completion.
nonisolated enum WorkoutFocusPolicy {
    struct Progress: Equatable, Sendable {
        let id: UUID
        let pendingSets: Int
    }

    static func resolve(selected: UUID?, exercises: [Progress]) -> UUID? {
        if let selected, exercises.contains(where: { $0.id == selected }) { return selected }
        return exercises.first(where: { $0.pendingSets > 0 })?.id ?? exercises.first?.id
    }

    static func next(after id: UUID, exercises: [Progress]) -> UUID? {
        guard let i = exercises.firstIndex(where: { $0.id == id }) else { return resolve(selected: nil, exercises: exercises) }
        let ordered = Array(exercises.dropFirst(i + 1)) + Array(exercises.prefix(i))
        return ordered.first(where: { $0.pendingSets > 0 })?.id
    }
}
