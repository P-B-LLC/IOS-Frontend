import Foundation
import XCTest
@testable import AccountSafety

final class WorkoutSessionPolicyTests: XCTestCase {
    // MARK: - Set kinds

    func testOnlyNormalSetsAreNumberedAndOthersShowTheirLetter() {
        XCTAssertEqual(WorkoutSetPolicy.labels(for: [.warmup, .normal, .normal, .failure, .drop]),
                       ["W", "1", "2", "F", "D"])
        XCTAssertEqual(WorkoutSetPolicy.labels(for: []), [])
    }

    func testSetKindsChangeBehaviourNotOnlyLabels() {
        XCTAssertFalse(WorkoutSetType.warmup.countsAsWorkingSet)
        XCTAssertTrue(WorkoutSetType.failure.countsAsWorkingSet)
        XCTAssertTrue(WorkoutSetType.drop.followsWithoutRest)
        XCTAssertFalse(WorkoutSetType.normal.followsWithoutRest)
    }

    func testHintsMatchByKindAndPlaceSoAnAddedWarmupDoesNotShiftThem() {
        let lastTime: [WorkoutSetType] = [.normal, .normal, .normal]
        let today: [WorkoutSetType] = [.warmup, .normal, .normal, .normal]
        XCTAssertNil(WorkoutSetPolicy.previousIndex(at: 0, types: today, previousTypes: lastTime),
                     "A warm-up is never compared with last week's working set")
        XCTAssertEqual(WorkoutSetPolicy.previousIndex(at: 1, types: today, previousTypes: lastTime), 0)
        XCTAssertEqual(WorkoutSetPolicy.previousIndex(at: 3, types: today, previousTypes: lastTime), 2)
    }

    func testExtraWorkingSetsAimAtTheLastOneAndWarmupsMatchWarmups() {
        let lastTime: [WorkoutSetType] = [.warmup, .normal, .normal]
        XCTAssertEqual(WorkoutSetPolicy.previousIndex(at: 3, types: [.warmup, .normal, .normal, .normal], previousTypes: lastTime), 2)
        XCTAssertEqual(WorkoutSetPolicy.previousIndex(at: 0, types: [.warmup, .normal], previousTypes: lastTime), 0)
        XCTAssertNil(WorkoutSetPolicy.previousIndex(at: 0, types: [.normal], previousTypes: []))
    }

    // MARK: - After a set is logged

    private func progress(_ id: UUID, group: Int? = nil, pending: [WorkoutSetType], logged: Int, rest: Int? = nil) -> WorkoutSetPolicy.ExerciseProgress {
        .init(id: id, supersetGroup: group, pendingTypes: pending, loggedCount: logged, restSeconds: rest)
    }

    func testLoggingStartsTheExercisesOwnRestOrTheDefault() {
        let a = UUID(), b = UUID()
        let exercises = [progress(a, pending: [.normal], logged: 1, rest: 120), progress(b, pending: [.normal], logged: 0)]
        XCTAssertEqual(WorkoutSetPolicy.afterLogging(exerciseID: a, exercises: exercises, defaultRestSeconds: 90, autoStartRest: true),
                       .rest(seconds: 120, focus: a))
        XCTAssertEqual(WorkoutSetPolicy.afterLogging(exerciseID: b, exercises: exercises, defaultRestSeconds: 90, autoStartRest: true),
                       .rest(seconds: 90, focus: b))
    }

    func testNoRestBeforeADropSetWhenTheTimerIsOffOrForAZeroRest() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(WorkoutSetPolicy.afterLogging(exerciseID: a, exercises: [progress(a, pending: [.drop], logged: 2)],
                                                     defaultRestSeconds: 90, autoStartRest: true), .stay(focus: a))
        XCTAssertEqual(WorkoutSetPolicy.afterLogging(exerciseID: a, exercises: [progress(a, pending: [.normal], logged: 1)],
                                                     defaultRestSeconds: 90, autoStartRest: false), .stay(focus: a))
        XCTAssertEqual(WorkoutSetPolicy.afterLogging(exerciseID: b, exercises: [progress(b, pending: [.normal], logged: 1, rest: 0)],
                                                     defaultRestSeconds: 90, autoStartRest: true), .stay(focus: b))
    }

    func testFinishingAnExerciseRestsThenFocusesTheNextUnfinishedOne() {
        let a = UUID(), b = UUID(), c = UUID()
        let exercises = [progress(a, pending: [], logged: 3), progress(b, pending: [], logged: 3), progress(c, pending: [.normal], logged: 0)]
        XCTAssertEqual(WorkoutSetPolicy.afterLogging(exerciseID: a, exercises: exercises, defaultRestSeconds: 60, autoStartRest: true),
                       .rest(seconds: 60, focus: c))
    }

    func testTheLastSetOfTheWorkoutStartsNoRest() {
        let a = UUID()
        XCTAssertEqual(WorkoutSetPolicy.afterLogging(exerciseID: a, exercises: [progress(a, pending: [], logged: 3)],
                                                     defaultRestSeconds: 90, autoStartRest: true), .stay(focus: nil))
    }

    func testASupersetMovesToItsPartnerAndRestsOnlyAtTheEndOfARound() {
        let a = UUID(), b = UUID(), c = UUID()
        // A's first set is in; B has not done the round yet.
        var exercises = [progress(a, group: 1, pending: [.normal, .normal], logged: 1),
                         progress(b, group: 1, pending: [.normal, .normal, .normal], logged: 0, rest: 75),
                         progress(c, pending: [.normal], logged: 0)]
        XCTAssertEqual(WorkoutSetPolicy.afterLogging(exerciseID: a, exercises: exercises, defaultRestSeconds: 90, autoStartRest: true),
                       .move(to: b))
        // B closes the round: rest with B's length, then back to A.
        exercises[1] = progress(b, group: 1, pending: [.normal, .normal], logged: 1, rest: 75)
        XCTAssertEqual(WorkoutSetPolicy.afterLogging(exerciseID: b, exercises: exercises, defaultRestSeconds: 90, autoStartRest: true),
                       .rest(seconds: 75, focus: a))
    }

    func testEstimatedDurationIsRoundedAndCountsRestBetweenSetsOnly() {
        // 3 sets: 3 × 45 s work + 2 × 90 s rest = 315 s ≈ 5 min.
        XCTAssertEqual(WorkoutSetPolicy.estimatedMinutes(sets: [(3, nil)], defaultRestSeconds: 90), 5)
        // 4 exercises × 4 sets, 2-minute rests: 16×45 + 12×120 = 2160 s = 36 min → 35.
        XCTAssertEqual(WorkoutSetPolicy.estimatedMinutes(sets: Array(repeating: (4, 120), count: 4), defaultRestSeconds: 90), 35)
        XCTAssertEqual(WorkoutSetPolicy.estimatedMinutes(sets: [], defaultRestSeconds: 90), 0)
    }

    // MARK: - Rest timer

    func testRestCountsFromItsEndDateWhateverTheAppWasDoing() {
        let start = Date(timeIntervalSince1970: 1_000)
        let timer = RestTimer.start(seconds: 90, exerciseID: nil, at: start)
        XCTAssertEqual(timer.phase(at: start.addingTimeInterval(30)), .running)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(30)), 60, accuracy: 0.001)
        // Locked phone for ten minutes: the timer is simply over, not frozen.
        XCTAssertEqual(timer.phase(at: start.addingTimeInterval(600)), .finished)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(600)), 0)
        XCTAssertEqual(timer.startedAt, start)
    }

    func testPauseHoldsTheRemainderAndResumeContinuesFromIt() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timer = RestTimer.start(seconds: 90, exerciseID: nil, at: start)
        timer.pause(at: start.addingTimeInterval(20))
        XCTAssertEqual(timer.phase(at: start.addingTimeInterval(500)), .paused)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(500)), 70, accuracy: 0.001)
        timer.resume(at: start.addingTimeInterval(500))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(510)), 60, accuracy: 0.001)
    }

    func testAdjustingResettingAndClampingKeepTheSameRest() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timer = RestTimer.start(seconds: 60, exerciseID: nil, at: start)
        let id = timer.id
        timer.adjust(by: 15, at: start)
        XCTAssertEqual(timer.remaining(at: start), 75, accuracy: 0.001)
        timer.adjust(by: -500, at: start)
        XCTAssertEqual(timer.phase(at: start), .finished, "Taking off more than is left ends the rest, never negative")
        timer.reset(at: start.addingTimeInterval(5))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(5)), 60, accuracy: 0.001)
        XCTAssertEqual(timer.id, id, "Adjusting never replaces the rest a Lock Screen button names")
        XCTAssertEqual(RestTimer.start(seconds: 99_999, exerciseID: nil, at: start).remaining(at: start), RestTimer.maximumSeconds)
    }

    func testRestTimerSurvivesACheckpointRoundTrip() throws {
        var timer = RestTimer.start(seconds: 120, exerciseID: UUID(), at: Date(timeIntervalSince1970: 1_000))
        timer.pause(at: Date(timeIntervalSince1970: 1_030))
        let decoded = try JSONDecoder().decode(RestTimer.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(decoded, timer)
        XCTAssertEqual(decoded.remaining(), 90, accuracy: 0.001)
    }

    func testClockText() {
        XCTAssertEqual(RestTimer.clockText(90), "1:30")
        XCTAssertEqual(RestTimer.clockText(59.2), "1:00", "Rounded up, so it never shows 0:00 while time is left")
        XCTAssertEqual(RestTimer.clockText(3720), "1:02:00")
    }

    // MARK: - Reshaping a session

    private func item(_ id: Int?, _ name: String, _ types: [WorkoutSetType] = [.normal, .normal, .normal],
                      rest: Int? = nil, group: Int? = nil) -> WorkoutStructure.Item {
        .init(workoutExerciseID: id, exerciseServerID: id.map { $0 + 1000 }, name: name, setTypes: types,
              restSeconds: rest, supersetGroup: group)
    }

    func testAnUnchangedSessionAsksNothing() {
        let plan = WorkoutStructure(items: [item(1, "Bench"), item(2, "Row")])
        XCTAssertTrue(WorkoutStructureDiff.changes(from: plan, to: plan).isEmpty)
    }

    func testAddingRemovingAndReorderingAreEachReportedOnce() {
        let plan = WorkoutStructure(items: [item(1, "Bench"), item(2, "Row"), item(3, "Fly")])
        let session = WorkoutStructure(items: [item(3, "Fly"), item(1, "Bench"), item(nil, "Dips")])
        XCTAssertEqual(WorkoutStructureDiff.changes(from: plan, to: session),
                       [.added("Dips"), .removed("Row"), .reordered])
    }

    func testRemovingOneExerciseIsNotAlsoAReorder() {
        let plan = WorkoutStructure(items: [item(1, "Bench"), item(2, "Row"), item(3, "Fly")])
        let session = WorkoutStructure(items: [item(1, "Bench"), item(3, "Fly")])
        XCTAssertEqual(WorkoutStructureDiff.changes(from: plan, to: session), [.removed("Row")])
    }

    func testSetsKindsRestAndSupersetChangesAreStructural() {
        let plan = WorkoutStructure(items: [item(1, "Bench"), item(2, "Row")])
        let session = WorkoutStructure(items: [
            item(1, "Bench", [.warmup, .normal, .normal, .normal], rest: 120, group: 1),
            item(2, "Row", [.normal, .normal, .drop], group: 1)
        ])
        XCTAssertEqual(WorkoutStructureDiff.changes(from: plan, to: session),
                       [.sets("Bench"), .rest("Bench"), .superset("Bench"), .setTypes("Row"), .superset("Row")])
    }

    func testRenumberedSupersetsAreTheSamePlan() {
        let plan = WorkoutStructure(items: [item(1, "Bench", group: 4), item(2, "Row", group: 4)])
        let session = WorkoutStructure(items: [item(1, "Bench", group: 1), item(2, "Row", group: 1)])
        XCTAssertTrue(WorkoutStructureDiff.changes(from: plan, to: session).isEmpty)
        XCTAssertEqual(WorkoutStructureDiff.normalizedSupersets([nil, 7, 7, 3, nil, 3]), [nil, 1, 1, 2, nil, 2])
    }

    func testStoredSetKindsDropTrailingNormalSets() {
        XCTAssertEqual(WorkoutStructureDiff.storedSetTypes([.warmup, .normal, .normal]), [.warmup])
        XCTAssertEqual(WorkoutStructureDiff.storedSetTypes([.normal, .drop, .normal]), [.normal, .drop])
        XCTAssertEqual(WorkoutStructureDiff.storedSetTypes([.normal]), [])
    }

    // MARK: - Weight units

    func testPoundsTypedComeBackExactlyAndSwitchingNeverMovesTheRecord() {
        let stored = WorkoutWeightUnit.imperial.kilograms(display: "135")
        XCTAssertEqual(stored, "61.23")
        XCTAssertEqual(WorkoutWeightUnit.imperial.display(kilograms: stored), "135")
        for typed in ["45", "102.5", "225", "315", "0.5", "1000"] {
            let kilograms = WorkoutWeightUnit.imperial.kilograms(display: typed)
            XCTAssertEqual(Decimal(string: WorkoutWeightUnit.imperial.display(kilograms: kilograms)), Decimal(string: typed), typed)
        }
        // Showing a weight in pounds and back is display only.
        XCTAssertEqual(WorkoutWeightUnit.metric.display(kilograms: stored), "61.23")
    }

    func testExactPoundFactor() {
        XCTAssertEqual(WorkoutWeightUnit.imperial.kilograms(display: "1"), "0.45")
        XCTAssertEqual(WorkoutWeightUnit.imperial.display(kilograms: "100"), "220.5")
        XCTAssertEqual(WorkoutWeightUnit.metric.toggled, .imperial)
    }

    // MARK: - Following

    func testTheButtonShowsYourSideAndTheBadgeShowsTheirs() {
        let none = FollowRelationship(outgoing: .none, followsViewer: false, isPrivate: false)
        XCTAssertEqual(none.action, .follow)
        XCTAssertNil(none.badge)

        let theyFollow = FollowRelationship(outgoing: .none, followsViewer: true, isPrivate: false)
        XCTAssertEqual(theyFollow.action, .followBack)
        XCTAssertEqual(theyFollow.badge, .followsYou)

        let oneWay = FollowRelationship(outgoing: .following, followsViewer: false, isPrivate: false)
        XCTAssertEqual(oneWay.action, .following)
        XCTAssertNil(oneWay.badge, "Not following you back is never pointed out")

        let mutual = FollowRelationship(outgoing: .following, followsViewer: true, isPrivate: false)
        XCTAssertEqual(mutual.action, .following)
        XCTAssertEqual(mutual.badge, .mutual)
        XCTAssertTrue(mutual.isMutual)
    }

    func testPrivateProfilesAreRequestedAndUnknownsShowNothing() {
        let closed = FollowRelationship(outgoing: .none, followsViewer: true, isPrivate: true)
        XCTAssertEqual(closed.action, .request)
        XCTAssertEqual(closed.badge, .followsYou)
        XCTAssertEqual(FollowRelationship(outgoing: .requested, followsViewer: nil, isPrivate: true).action, .requested)
        XCTAssertNil(FollowRelationship(outgoing: .none, followsViewer: nil, isPrivate: false).badge)
    }

    func testOnlyLeavingIsConfirmedAndTransitionsKeepTheirSide() {
        XCTAssertFalse(FollowRelationship(outgoing: .none, followsViewer: nil, isPrivate: false).confirmsBeforeLeaving)
        let following = FollowRelationship(outgoing: .following, followsViewer: true, isPrivate: false)
        XCTAssertTrue(following.confirmsBeforeLeaving)
        XCTAssertEqual(following.afterLeaving().action, .followBack)
        XCTAssertEqual(following.afterLeaving().badge, .followsYou)
        let start = FollowRelationship(outgoing: .none, followsViewer: false, isPrivate: true)
        XCTAssertEqual(start.afterFollowing(requested: true).action, .requested)
        XCTAssertEqual(start.afterFollowing(requested: false).action, .following)
    }
}
