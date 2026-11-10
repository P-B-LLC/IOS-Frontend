import Foundation
import XCTest
@testable import AccountSafety

/// Round progression uses successfully logged sets, never the contents of a
/// weight field. Bodyweight sets therefore participate in exactly the same way.
final class SupersetRoundPolicyTests: XCTestCase {
    private func progress(
        _ id: UUID,
        group: Int? = 1,
        total: Int = 3,
        logged: Int,
        rest: Int? = nil
    ) -> WorkoutSetPolicy.ExerciseProgress {
        .init(
            id: id,
            supersetGroup: group,
            pendingTypes: Array(repeating: .normal, count: max(total - logged, 0)),
            loggedCount: logged,
            restSeconds: rest
        )
    }

    private func decision(
        after id: UUID,
        _ exercises: [WorkoutSetPolicy.ExerciseProgress],
        autoStart: Bool = true
    ) -> WorkoutSetPolicy.AfterLog {
        WorkoutSetPolicy.afterLogging(
            exerciseID: id,
            exercises: exercises,
            defaultRestSeconds: 45,
            autoStartRest: autoStart
        )
    }

    func testLoggingTheSecondExerciseFirstMovesBackWithoutStartingRest() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(
            decision(after: b, [progress(a, logged: 0), progress(b, logged: 1)]),
            .move(to: a)
        )
    }

    func testReverseOrderStartsRestOnlyWhenTheEarlierExerciseClosesTheRound() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(
            decision(after: a, [progress(a, logged: 1, rest: 75), progress(b, logged: 1)]),
            .rest(seconds: 75, focus: a),
            "Use the rest setting on whichever exercise actually closes the round."
        )
    }

    func testEveryThreeExerciseOrderWaitsForAllPartners() {
        let ids = [UUID(), UUID(), UUID()]
        let orders = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for order in orders {
            var logged = [0, 0, 0]
            for (step, index) in order.enumerated() {
                logged[index] += 1
                let exercises = ids.indices.map { progress(ids[$0], logged: logged[$0]) }
                let result = decision(after: ids[index], exercises)
                if step < 2 {
                    guard case .move(let next) = result else {
                        XCTFail("Rest began before every partner saved: order \(order), step \(step), \(result)")
                        continue
                    }
                    let nextIndex = ids.firstIndex(of: next)!
                    XCTAssertEqual(logged[nextIndex], 0, "Focus must go to a partner who still owes the round.")
                } else {
                    XCTAssertEqual(result, .rest(seconds: 45, focus: ids[0]))
                }
            }
        }
    }

    func testLaterRoundsWaitForEarlierPartnersToo() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(
            decision(after: b, [progress(a, logged: 1), progress(b, logged: 2)]),
            .move(to: a)
        )
        XCTAssertEqual(
            decision(after: a, [progress(a, logged: 2), progress(b, logged: 2)]),
            .rest(seconds: 45, focus: a)
        )
    }

    func testPartnerBehindInTheNextRoundGetsFocusAfterRest() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(
            decision(after: b, [progress(a, logged: 2), progress(b, logged: 1)]),
            .rest(seconds: 45, focus: b),
            "A has already logged its second set; B still owes the next round."
        )
    }

    func testCyclicFocusPrefersTheNextUnfinishedPartnerThenWraps() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(
            decision(after: b, [progress(a, logged: 0), progress(b, logged: 1), progress(c, logged: 0)]),
            .move(to: c)
        )
        XCTAssertEqual(
            decision(after: c, [progress(a, logged: 0), progress(b, logged: 1), progress(c, logged: 1)]),
            .move(to: a)
        )
    }

    func testCompletedShorterPartnerDoesNotBlockRemainingRounds() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(
            decision(after: b, [progress(a, total: 1, logged: 1), progress(b, logged: 2)]),
            .rest(seconds: 45, focus: b)
        )
    }

    func testCompletingShorterPartnerStillWaitsForAnUnloggedEarlierPartner() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(
            decision(after: b, [progress(a, logged: 0), progress(b, total: 1, logged: 1)]),
            .move(to: a)
        )
    }

    func testFinalSupersetRoundMovesOnAfterRestIfOtherExercisesRemain() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(
            decision(after: a, [progress(a, total: 1, logged: 1), progress(b, total: 1, logged: 1),
                                progress(c, group: nil, logged: 0)]),
            .rest(seconds: 45, focus: c)
        )
    }

    func testFinalWorkoutSetDoesNotStartAnUnnecessaryRest() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(
            decision(after: a, [progress(a, total: 1, logged: 1), progress(b, total: 1, logged: 1)]),
            .stay(focus: nil)
        )
    }

    func testOtherGroupsNeverHoldUpTheCompletedRound() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(
            decision(after: b, [progress(a, logged: 1), progress(c, group: 2, logged: 0), progress(b, logged: 1)]),
            .rest(seconds: 45, focus: a)
        )
    }

    func testUngroupedExercisesAreNotTreatedAsOneSuperset() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(
            decision(after: b, [progress(a, group: nil, logged: 0), progress(b, group: nil, logged: 1)]),
            .rest(seconds: 45, focus: b)
        )
    }

    func testNoWeightInputIsRequiredToCountALoggedBodyweightPartner() {
        // Progress deliberately has no weight field. These equally represent
        // a saved weighted set and a saved bodyweight set.
        let weighted = UUID(), bodyweight = UUID()
        XCTAssertEqual(
            decision(after: bodyweight, [progress(weighted, logged: 0), progress(bodyweight, logged: 1)]),
            .move(to: weighted)
        )
        XCTAssertEqual(
            decision(after: weighted, [progress(weighted, logged: 1), progress(bodyweight, logged: 1)]),
            .rest(seconds: 45, focus: weighted)
        )
    }

    func testAutoRestOffStillMovesToTheUnfinishedPartner() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(
            decision(after: b, [progress(a, logged: 0), progress(b, logged: 1)], autoStart: false),
            .move(to: a)
        )
        XCTAssertEqual(
            decision(after: a, [progress(a, logged: 1), progress(b, logged: 1)], autoStart: false),
            .stay(focus: a)
        )
    }

    func testZeroRestSettingStillWaitsForThePartnerAndNeverStartsATimer() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(
            decision(after: b, [progress(a, logged: 0, rest: 0), progress(b, logged: 1, rest: 0)]),
            .move(to: a)
        )
        XCTAssertEqual(
            decision(after: a, [progress(a, logged: 1, rest: 0), progress(b, logged: 1, rest: 0)]),
            .stay(focus: a)
        )
    }

    func testNonSupersetDropContinuationStillSkipsRest() {
        let a = UUID()
        let exercise = WorkoutSetPolicy.ExerciseProgress(
            id: a, supersetGroup: nil, pendingTypes: [.drop], loggedCount: 1, restSeconds: 45
        )
        XCTAssertEqual(decision(after: a, [exercise]), .stay(focus: a))
    }

    func testWarmupRowsStillWaitForTheirSupersetPartner() {
        let a = UUID(), b = UUID()
        let exercises: [WorkoutSetPolicy.ExerciseProgress] = [
            .init(id: a, supersetGroup: 1, pendingTypes: [.warmup, .normal], loggedCount: 0, restSeconds: nil),
            .init(id: b, supersetGroup: 1, pendingTypes: [.normal], loggedCount: 1, restSeconds: nil)
        ]
        XCTAssertEqual(decision(after: b, exercises), .move(to: a))
    }
}
