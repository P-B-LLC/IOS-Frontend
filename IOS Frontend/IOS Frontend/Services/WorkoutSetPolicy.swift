import Foundation

/// The decisions a lifting session makes between sets, kept apart from the
/// store so they can be tested without a server or a screen.
nonisolated enum WorkoutSetPolicy {
    /// What a set row shows in its first column: a working set's place in the
    /// working count, or the letter of any other kind.
    ///
    /// Only normal sets are counted, so "W, 1, 2, F" reads as two working sets
    /// and a set to failure rather than as a fourth set with a gap before it.
    static func labels(for types: [WorkoutSetType]) -> [String] {
        var ordinal = 0
        return types.map { type in
            guard let badge = type.badge else {
                ordinal += 1
                return "\(ordinal)"
            }
            return badge
        }
    }

    /// Which of last time's sets a row should be compared against.
    ///
    /// Matched by kind and place rather than by set number. A warm-up added
    /// today in front of the working sets would otherwise shift every hint
    /// down a row, and the first working set would be measured against last
    /// week's warm-up. Warm-ups are matched against warm-ups; every working
    /// set against the working set in the same place, falling back to the
    /// last one when today has more of them than last time did.
    static func previousIndex(
        at position: Int,
        types: [WorkoutSetType],
        previousTypes: [WorkoutSetType]
    ) -> Int? {
        guard types.indices.contains(position), !previousTypes.isEmpty else { return nil }
        let warmup = !types[position].countsAsWorkingSet
        let place = types[..<position].filter { $0.countsAsWorkingSet != warmup }.count
        let candidates = previousTypes.indices.filter { previousTypes[$0].countsAsWorkingSet != warmup }
        guard !candidates.isEmpty else {
            // Last time had no set of this kind. A working set still has
            // something useful to aim at in the same row number; a warm-up
            // compared against a working set would only mislead.
            return warmup ? nil : (previousTypes.indices.contains(position) ? position : previousTypes.indices.last)
        }
        return candidates.indices.contains(place) ? candidates[place] : candidates.last
    }

    // MARK: - After a set is logged

    /// One exercise as the between-sets decision sees it.
    struct ExerciseProgress: Equatable, Sendable {
        let id: UUID
        let supersetGroup: Int?
        /// The kinds of the sets not yet logged, in order.
        let pendingTypes: [WorkoutSetType]
        let loggedCount: Int
        /// Seconds to rest after this exercise's sets; nil means the person's
        /// default, and zero means no timer at all.
        let restSeconds: Int?
    }

    enum AfterLog: Equatable, Sendable {
        /// Rest this long, then carry on with this exercise.
        case rest(seconds: Int, focus: UUID?)
        /// Go straight to another exercise: the next one in a superset.
        case move(to: UUID)
        /// Stay where you are with no timer: a drop set is next, the timer is
        /// switched off, or there is nothing left to do.
        case stay(focus: UUID?)
    }

    /// What should happen after a set of `exerciseID` has just been logged.
    ///
    /// A superset is done a round at a time, one set of each exercise in turn,
    /// so the rest belongs to the end of the round rather than to every set.
    /// The rest length is the one set on the exercise that closes the round.
    static func afterLogging(
        exerciseID: UUID,
        exercises: [ExerciseProgress],
        defaultRestSeconds: Int,
        autoStartRest: Bool
    ) -> AfterLog {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else {
            return .stay(focus: nil)
        }
        let current = exercises[index]
        let anythingLeft = exercises.contains { !$0.pendingTypes.isEmpty }
        guard anythingLeft else { return .stay(focus: nil) }

        if let group = current.supersetGroup {
            let members = exercises.filter { $0.supersetGroup == group }
            // The next exercise in this round: later in the group, still
            // owing a set, and behind the one just logged.
            if let position = members.firstIndex(where: { $0.id == exerciseID }),
               let next = members[(position + 1)...].first(where: {
                   !$0.pendingTypes.isEmpty && $0.loggedCount < current.loggedCount
               }) {
                return .move(to: next.id)
            }
            // The round is over. Back to the first exercise of the group that
            // still owes a set, after the rest.
            let first = members.first { !$0.pendingTypes.isEmpty }?.id
            return rest(after: current, focus: first ?? nextFocus(after: index, in: exercises),
                        defaultRestSeconds: defaultRestSeconds, autoStartRest: autoStartRest)
        }

        if current.pendingTypes.first?.followsWithoutRest == true {
            return .stay(focus: current.id)
        }
        let focus = current.pendingTypes.isEmpty ? nextFocus(after: index, in: exercises) : current.id
        return rest(after: current, focus: focus,
                    defaultRestSeconds: defaultRestSeconds, autoStartRest: autoStartRest)
    }

    private static func rest(
        after exercise: ExerciseProgress,
        focus: UUID?,
        defaultRestSeconds: Int,
        autoStartRest: Bool
    ) -> AfterLog {
        let seconds = exercise.restSeconds ?? defaultRestSeconds
        guard autoStartRest, seconds > 0 else { return .stay(focus: focus) }
        return .rest(seconds: seconds, focus: focus)
    }

    /// The next exercise with anything left, searching forward and then from
    /// the top, so finishing the last card returns to one skipped earlier.
    static func nextFocus(after index: Int, in exercises: [ExerciseProgress]) -> UUID? {
        let ordered = Array(exercises[(index + 1)...]) + Array(exercises[...index])
        return ordered.first { !$0.pendingTypes.isEmpty }?.id
    }

    /// Rough time a plan takes, for a saved workout's card: about forty-five
    /// seconds of work per set, plus each exercise's rest after every set but
    /// its last. Shown as an estimate, never as a promise.
    static func estimatedMinutes(
        sets: [(count: Int, restSeconds: Int?)],
        defaultRestSeconds: Int,
        workSecondsPerSet: Int = 45
    ) -> Int {
        let seconds = sets.reduce(0) { total, exercise in
            let count = max(exercise.count, 0)
            let rest = max(exercise.restSeconds ?? defaultRestSeconds, 0)
            return total + count * workSecondsPerSet + max(count - 1, 0) * rest
        }
        guard seconds > 0 else { return 0 }
        // Rounded to five minutes: a number this rough should not look exact.
        let minutes = Double(seconds) / 60
        return max(5, Int((minutes / 5).rounded()) * 5)
    }
}
