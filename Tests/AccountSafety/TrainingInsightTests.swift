import Foundation
import XCTest
@testable import AccountSafety

final class TrainingInsightTests: XCTestCase {
    private func stats(completed: Int, planned: Int, history: [Int] = [0, 0, 0, 0, 0, 0]) -> TrainingStats {
        TrainingStats(totalWorkouts: completed, completedThisWeek: completed,
            completedThisMonth: completed, currentStreakWeeks: 0,
            bestStreakWeeks: 0, sixWeekCounts: history, weeklyGoal: planned)
    }

    func testNoScheduleNeverDividesByZeroOrClaimsGoalCompletion() {
        let value = stats(completed: 3, planned: 0)
        XCTAssertEqual(value.weeklyPlanProgress, 0)
        XCTAssertTrue(value.weeklyEncouragement.contains("without a schedule"))
    }

    func testExtraSessionsClampProgressWithoutClaimingSpecificWorkoutsCompleted() {
        let value = stats(completed: 6, planned: 4)
        XCTAssertEqual(value.weeklyPlanProgress, 1)
        XCTAssertTrue(value.weeklyEncouragement.contains("as many sessions"))
        XCTAssertTrue(value.weeklyEncouragement.contains("recover"))
    }

    func testPartialWeekAndNewAccountHaveHonestProgress() {
        XCTAssertEqual(stats(completed: 1, planned: 4).weeklyPlanProgress, 0.25)
        XCTAssertTrue(TrainingStats.empty.weeklyEncouragement.contains("rest day"))
        XCTAssertEqual(TrainingStats.empty.previousWeekCount, 0)
    }

    func testEmptyHistoryAndZeroBarsDoNotInventActivity() {
        let empty = stats(completed: 0, planned: 0, history: [])
        XCTAssertEqual(empty.barHeight(for: 0), 0)
        XCTAssertEqual(empty.previousWeekCount, 0)
        let value = stats(completed: 2, planned: 4, history: [3, 0, 5, 1, 4, 2])
        XCTAssertEqual(value.previousWeekCount, 4)
        XCTAssertEqual(value.barHeight(for: 0), 0)
        XCTAssertEqual(value.barHeight(for: 5), 82)
    }
}
