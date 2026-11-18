import Foundation

/// A reusable target, not a performed set. IDs survive editing and reordering;
/// kilograms remain canonical regardless of the session's display unit.
nonisolated struct WorkoutPlannedSet: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var setType: WorkoutSetType
    var targetReps: Int?
    var targetWeightKilograms: String?

    init(id: UUID = UUID(), setType: WorkoutSetType = .normal,
         targetReps: Int? = nil, targetWeightKilograms: String? = nil) {
        self.id = id
        self.setType = setType
        self.targetReps = targetReps
        self.targetWeightKilograms = targetWeightKilograms
    }

    /// Legacy targets apply only to working sets. Deterministic local IDs keep
    /// untouched legacy drafts stable; the server supplies its own snapshot IDs.
    static func legacy(exerciseID: UUID, types: [WorkoutSetType], reps: Int?, weight: String?) -> [Self] {
        types.enumerated().map { index, kind in
            var bytes = exerciseID.uuid
            let number = UInt32(index + 1)
            // Server-derived exercise UUIDs store their relation ID in the
            // lower eight bytes. Keep that identity intact across exercises.
            bytes.0 ^= 0x9D
            bytes.4 ^= UInt8(truncatingIfNeeded: number >> 24)
            bytes.5 ^= UInt8(truncatingIfNeeded: number >> 16)
            bytes.6 ^= UInt8(truncatingIfNeeded: number >> 8)
            bytes.7 ^= UInt8(truncatingIfNeeded: number)
            return Self(id: UUID(uuid: bytes), setType: kind,
                        targetReps: kind.countsAsWorkingSet ? reps.flatMap { $0 > 0 ? $0 : nil } : nil,
                        targetWeightKilograms: kind.countsAsWorkingSet ? weight : nil)
        }
    }
}

nonisolated enum WorkoutPlannedSetPolicy {
    static let maximumCount = 50

    /// Wire precision is two decimal places. Reject malformed or out-of-range
    /// input rather than silently omitting a target the person meant to save.
    static func canonicalWeight(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.range(of: #"^[0-9]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0, decimal <= Decimal(string: "99999.99")! else { return nil }
        return NSDecimalNumber(decimal: decimal).stringValue
    }

    static func isValid(_ rows: [WorkoutPlannedSet]) -> Bool {
        guard rows.count <= maximumCount, Set(rows.map(\.id)).count == rows.count else { return false }
        return rows.allSatisfy { row in
            (row.targetReps.map { (1...1000).contains($0) } ?? true)
                && (row.targetWeightKilograms.map { canonicalWeight($0) != nil } ?? true)
        }
    }

    static func sameTargets(_ lhs: [WorkoutPlannedSet], _ rhs: [WorkoutPlannedSet]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { a, b in
            a.id == b.id && a.setType == b.setType && a.targetReps == b.targetReps
                && canonicalWeight(a.targetWeightKilograms) == canonicalWeight(b.targetWeightKilograms)
        }
    }
}
