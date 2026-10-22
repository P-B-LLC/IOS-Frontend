import Foundation

/// Rewards only an observed crossing with an unchanged goal on the same day.
/// Opening a page, a missing Health reading, or lowering a goal is not a win.
nonisolated struct StepGoalCelebrationGate {
    private var previous: (day: Date, steps: Int, goal: Int)?
    private var rewardedDays: Set<Date> = []

    mutating func observe(day: Date, steps: Int?, goal: Int) -> Bool {
        guard let steps, goal > 0 else { previous = nil; return false }
        let old = previous
        previous = (day, steps, goal)
        guard let old, old.day == day, old.goal == goal,
              old.steps < goal, steps >= goal,
              rewardedDays.insert(day).inserted else { return false }
        return true
    }

    mutating func rebase(day: Date, steps: Int?, goal: Int) {
        previous = steps.map { (day, $0, goal) }
    }
}
