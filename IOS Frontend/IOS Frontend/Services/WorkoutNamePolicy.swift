import Foundation

/// The API requires exact workout names to be unique per account. A new
/// plan keeps its own identity and selections when its name is changed.
nonisolated enum WorkoutNamePolicy {
    static func conflicts(_ name: String, with savedNames: [String]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && savedNames.contains(trimmed)
    }

    static func blocksCreate(name: String, savedNames: [String], serverID: Int?, hasPendingSave: Bool) -> Bool {
        // A matching library row can be this operation's committed write.
        // Keep its original idempotent retry available until confirmed.
        serverID == nil && !hasPendingSave && conflicts(name, with: savedNames)
    }

    static func availableName(for name: String, savedNames: [String]) -> String {
        let base = prefix(name.trimmingCharacters(in: .whitespacesAndNewlines), scalars: 150)
        let taken = Set(savedNames)
        guard taken.contains(base) else { return base }
        var number = 2
        while true {
            let suffix = " (\(number))"
            let candidate = prefix(base, scalars: 150 - suffix.count) + suffix
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    private static func prefix(_ value: String, scalars: Int) -> String {
        var result = String()
        result.unicodeScalars.append(contentsOf: value.unicodeScalars.prefix(scalars))
        return result
    }
}
