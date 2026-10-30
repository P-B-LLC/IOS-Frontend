import Foundation
import XCTest
@testable import AccountSafety

/// A session in progress is checkpointed to disk and restored after a
/// relaunch -- including the relaunch an app update causes. A checkpoint
/// written by the previous build has none of the fields this one added, and
/// failing to read it would lose the workout being trained.
final class WorkoutCheckpointTests: XCTestCase {
    private func session() -> ActiveWorkoutSession {
        let exercise = SessionExerciseDraft(
            id: UUID(), exerciseServerID: 11, sessionExerciseID: 101, name: "Bench Press",
            sets: [
                WorkoutSetDraft(serverID: 900, setNumber: 1, weightKilograms: "40", reps: "10", isLogged: true, setType: .warmup),
                WorkoutSetDraft(setNumber: 2, setType: .normal)
            ],
            workoutExerciseID: 1, restSeconds: 120, supersetGroup: nil, targetReps: 8, targetWeightKilograms: "60"
        )
        var session = ActiveWorkoutSession(
            id: UUID(), serverID: 4242, day: .monday, workoutID: UUID(), workoutServerID: 7,
            workoutName: "Push Day", workoutType: .lifting, startedAt: Date(timeIntervalSince1970: 1_000),
            exercises: [exercise],
            restTimer: .start(seconds: 90, exerciseID: exercise.id, at: Date(timeIntervalSince1970: 1_100)),
            focusedExerciseID: exercise.id
        )
        session.plan = session.structure
        return session
    }

    /// Encodes, then removes every key this release introduced, the way a
    /// checkpoint from the previous build looks on disk.
    private func previousBuildCheckpoint(_ session: ActiveWorkoutSession) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        for key in ["restTimer", "plan", "focusedExerciseID", "orderNeedsSync"] { object.removeValue(forKey: key) }
        object["exercises"] = (object["exercises"] as? [[String: Any]])?.map { exercise in
            var exercise = exercise
            for key in ["workoutExerciseID", "restSeconds", "supersetGroup", "targetReps", "targetWeightKilograms"] {
                exercise.removeValue(forKey: key)
            }
            exercise["sets"] = (exercise["sets"] as? [[String: Any]])?.map { set in
                var set = set
                set.removeValue(forKey: "setType")
                return set
            }
            return exercise
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testACheckpointFromThePreviousBuildStillRestores() throws {
        let original = session()
        let restored = try JSONDecoder().decode(ActiveWorkoutSession.self, from: previousBuildCheckpoint(original))
        XCTAssertEqual(restored.serverID, 4242)
        XCTAssertEqual(restored.loggedSetCount, 1, "logged sets survive the update")
        XCTAssertEqual(restored.exercises[0].sets.map(\.setType), [.normal, .normal], "missing kinds read as normal")
        XCTAssertNil(restored.restTimer)
        XCTAssertNil(restored.plan, "no plan means the update question is simply not asked")
        XCTAssertTrue(restored.structureChanges.isEmpty)
        XCTAssertFalse(restored.orderNeedsSync)
    }

    func testTheCurrentCheckpointRoundTripsEverything() throws {
        let original = session()
        let restored = try JSONDecoder().decode(ActiveWorkoutSession.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.restTimer?.remaining(at: Date(timeIntervalSince1970: 1_130)) ?? 0, 60, accuracy: 0.001)
    }

    func testAPlanDraftFromThePreviousBuildStillOpens() throws {
        let draft = Workout(name: "Push Day", exercises: [Exercise(name: "Bench Press", sets: 4)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        object["exercises"] = (object["exercises"] as? [[String: Any]])?.map { exercise in
            var exercise = exercise
            for key in ["setTypes", "restSeconds", "supersetGroup", "targetReps", "targetWeightKilograms"] {
                exercise.removeValue(forKey: key)
            }
            return exercise
        }
        let restored = try JSONDecoder().decode(Workout.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.exercises[0].plannedSetTypes, [.normal, .normal, .normal, .normal])
    }

    func testWarmupsNeverOfferTheWorkingTarget() {
        let exercise = session().exercises[0]
        XCTAssertNil(exercise.targetReps(for: exercise.sets[0]))
        XCTAssertNil(exercise.targetWeightKilograms(for: exercise.sets[0]))
        XCTAssertEqual(exercise.targetReps(for: exercise.sets[1]), 8)
        XCTAssertEqual(exercise.targetWeightKilograms(for: exercise.sets[1]), "60")
    }

    func testReshapingIsDetectedAgainstThePlanSnapshot() {
        var session = session()
        XCTAssertTrue(session.structureChanges.isEmpty)
        session.exercises[0].sets.append(WorkoutSetDraft(setNumber: 3, setType: .drop))
        XCTAssertEqual(session.structureChanges, [.sets("Bench Press")])
        // Weights and reps are not structure.
        var trained = self.session()
        trained.exercises[0].sets[1].weightKilograms = "62.5"
        XCTAssertTrue(trained.structureChanges.isEmpty)
    }

    func testPlannedSetKindsAreStoredWithoutTrailingNormals() {
        var exercise = Exercise(name: "Bench Press", sets: 4)
        exercise.setType(.warmup, at: 0)
        exercise.setType(.drop, at: 3)
        XCTAssertEqual(exercise.setTypes, [.warmup, .normal, .normal, .drop])
        exercise.setType(.normal, at: 3)
        XCTAssertEqual(exercise.setTypes, [.warmup])
        XCTAssertEqual(exercise.plannedSetTypes, [.warmup, .normal, .normal, .normal])
    }

    func testSetNumbersAreNeverReusedAfterADelete() {
        var exercise = session().exercises[0]
        exercise.sets.append(WorkoutSetDraft(setNumber: 5))
        exercise.sets.removeAll { $0.setNumber == 2 }
        XCTAssertEqual(exercise.nextSetNumber, 6)
    }
}
