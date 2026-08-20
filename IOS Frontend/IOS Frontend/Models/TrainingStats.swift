//
//  TrainingStats.swift
//  IOS Frontend
//
//  The training record, as the server counts it.
//
//  Every figure here was once worked out on the device, which meant paging the
//  whole session history to the phone on each visit to the dashboard so it
//  could reduce it. The numbers are a property of the history and the history
//  lives on the server; the app asks and draws the answer.
//

import Foundation

nonisolated struct TrainingStats: Hashable, Sendable {
    let totalWorkouts: Int
    let completedThisWeek: Int
    let completedThisMonth: Int
    let currentStreakWeeks: Int
    let bestStreakWeeks: Int
    /// Six weekly counts, oldest first, ending with the current week.
    let sixWeekCounts: [Int]
    /// Workouts scheduled in the current week.
    let weeklyGoal: Int

    /// What is shown before the first answer arrives. Zeros rather than
    /// placeholder text, because the dashboard's shape should not change when
    /// the numbers land.
    static let empty = TrainingStats(
        totalWorkouts: 0,
        completedThisWeek: 0,
        completedThisMonth: 0,
        currentStreakWeeks: 0,
        bestStreakWeeks: 0,
        sixWeekCounts: Array(repeating: 0, count: 6),
        weeklyGoal: 0
    )

    // MARK: - Wording
    //
    // Formatting is the one thing left to the device: turning a number into a
    // phrase is presentation, and shipping "3 weeks" from the server would put
    // English in the database.

    var currentStreakText: String {
        "\(currentStreakWeeks) \(currentStreakWeeks == 1 ? "week" : "weeks")"
    }

    var bestStreakText: String {
        "\(bestStreakWeeks) \(bestStreakWeeks == 1 ? "week" : "weeks")"
    }

    var monthDetail: String {
        completedThisMonth == 0 ? "None this month" : "+\(completedThisMonth) this month"
    }

    /// Change between the last full week and this one.
    private var trendPercent: Int {
        guard sixWeekCounts.count >= 2 else { return 0 }
        let prior = sixWeekCounts[sixWeekCounts.count - 2]
        let current = sixWeekCounts[sixWeekCounts.count - 1]
        guard prior > 0 else { return current > 0 ? 100 : 0 }
        return Int(((Double(current - prior) / Double(prior)) * 100).rounded())
    }

    var trendPercentText: String { String(format: "%+d%%", trendPercent) }

    var trendLabel: String {
        trendPercent > 0 ? "Improving" : trendPercent < 0 ? "Easing" : "Steady"
    }

    var trendSymbol: String {
        trendPercent > 0
            ? "arrow.up.right"
            : trendPercent < 0 ? "arrow.down.right" : "arrow.right"
    }

    /// The next round number of workouts to aim at.
    var nextMilestone: Int { ((totalWorkouts / 10) + 1) * 10 }

    var workoutsToMilestone: Int { nextMilestone - totalWorkouts }

    var milestoneTitle: String {
        "\(workoutsToMilestone) workout\(workoutsToMilestone == 1 ? "" : "s") to reach \(nextMilestone)"
    }

    /// How far through the current block of ten, not how far from zero. The
    /// bar is about the next milestone, so at 91 workouts it should read
    /// nearly empty rather than nearly full.
    var milestoneProgress: Double {
        let start = max(nextMilestone - 10, 0)
        return Double(totalWorkouts - start) / Double(max(nextMilestone - start, 1))
    }

    /// Bar height for one week of the trend chart. Pure layout.
    func barHeight(for count: Int) -> CGFloat {
        let maximum = max(sixWeekCounts.max() ?? 0, 1)
        return max(12, 82 * CGFloat(count) / CGFloat(maximum))
    }
}
