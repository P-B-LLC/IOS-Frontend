import Foundation
import XCTest
@testable import AccountSafety

final class WorkoutActivityTests: XCTestCase {
    // MARK: - The registry

    func testEveryActivityIsConsistentWithItsProfile() {
        for activity in WorkoutActivity.allCases {
            XCTAssertEqual(activity.usesSets, activity.profile == .strength, "\(activity)")
            if activity.usesSets {
                XCTAssertEqual(activity.family, .lifting, "\(activity): sets are only ever lifting to old builds")
                XCTAssertEqual(activity.distanceField, .none, "\(activity)")
                XCTAssertTrue(activity.detailFields.isEmpty, "\(activity)")
            }
            if activity.tracksRoute {
                XCTAssertEqual(activity.profile, .distance, "\(activity): only distance activities record a route")
            }
            XCTAssertEqual(activity.distanceField == .primary, activity.profile == .distance, "\(activity)")
            for field in activity.detailFields where field.kind == .choice {
                XCTAssertFalse(field.options(for: activity).isEmpty, "\(activity) asks \(field) with no answers")
            }
            XCTAssertFalse(activity.title.isEmpty)
            XCTAssertFalse(activity.symbol.isEmpty)
        }
    }

    func testRawValuesAreTheServersSnakeCaseSlugs() {
        let raw = WorkoutActivity.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raw).count, raw.count)
        for value in raw {
            XCTAssertNotNil(value.range(of: #"^[a-z]+(_[a-z]+)*$"#, options: .regularExpression), value)
        }
        XCTAssertEqual(raw.count, 51, "Keep in step with repbase core/activities.py")
        XCTAssertEqual(WorkoutActivity.tableTennis.rawValue, "table_tennis")
        XCTAssertEqual(WorkoutActivity.openWaterSwimming.rawValue, "open_water_swimming")
    }

    func testLegacyTypesReadAsTheActivityTheyAlwaysMeant() {
        XCTAssertEqual(WorkoutActivity.legacyDefault(for: .lifting), .weightlifting)
        XCTAssertEqual(WorkoutActivity.legacyDefault(for: .running), .running)
        XCTAssertEqual(WorkoutActivity.legacyDefault(for: .biking), .cycling)
        XCTAssertEqual(WorkoutActivity.legacyDefault(for: .swimming), .swimming)
        for type in WorkoutType.allCases {
            XCTAssertEqual(WorkoutActivity.legacyDefault(for: type).family, type)
        }
    }

    func testAnActivityThisBuildDoesNotKnowNeverBreaksTheList() throws {
        XCTAssertEqual(WorkoutActivity(serverValue: "underwater_hockey", family: .lifting), .other)
        XCTAssertEqual(WorkoutActivity(serverValue: nil, family: .biking), .cycling)
        XCTAssertEqual(WorkoutActivity(serverValue: "", family: .running), .running)
        XCTAssertEqual(WorkoutActivity(serverValue: "tennis", family: .lifting), .tennis)
        let decoded = try JSONDecoder().decode([WorkoutActivity].self, from: Data(#"["padel","quidditch"]"#.utf8))
        XCTAssertEqual(decoded, [.padel, .other])
    }

    func testSearchFindsActivitiesByTheirEverydayNames() {
        XCTAssertTrue(WorkoutActivity.matching("ping pong").contains(.tableTennis))
        XCTAssertTrue(WorkoutActivity.matching("football").contains(.soccer))
        XCTAssertTrue(WorkoutActivity.matching("football").contains(.americanFootball))
        XCTAssertTrue(WorkoutActivity.matching("jog").contains(.jogging))
        XCTAssertTrue(WorkoutActivity.matching("BJJ").contains(.martialArts))
        XCTAssertEqual(WorkoutActivity.matching("  ").count, WorkoutActivity.allCases.count)
        XCTAssertTrue(WorkoutActivity.matching("zzzz").isEmpty)
        // Every activity belongs to exactly one group shown in the picker.
        XCTAssertEqual(ActivityCategory.allCases.flatMap(\.activities).count, WorkoutActivity.allCases.count)
    }

    // MARK: - Workouts and sessions saved before activities

    func testAWorkoutKeepsItsTypeInStepWithItsActivity() throws {
        var workout = Workout(name: "Tuesday", type: .running)
        XCTAssertEqual(workout.activity, .running)
        workout.activity = .tennis
        XCTAssertEqual(workout.type, .lifting)
        XCTAssertTrue(workout.tracksDistance, "A match is timed, not logged as sets")
        XCTAssertTrue(workout.exercises.isEmpty)
        workout.activity = .calisthenics
        XCTAssertFalse(workout.tracksDistance)

        let old = #"{"id":"6F1E0B6C-55B5-4B6F-9D52-4B0F2A1F3C11","name":"Ride","type":"biking","exercises":[]}"#
        let decoded = try JSONDecoder().decode(Workout.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.activity, .cycling)
        let roundTrip = try JSONDecoder().decode(Workout.self, from: JSONEncoder().encode(workout))
        XCTAssertEqual(roundTrip, workout)
    }

    func testARecoveredSessionFromBeforeActivitiesStillOpens() throws {
        let session = ActiveWorkoutSession(
            id: UUID(), serverID: 9, day: .monday, workoutID: UUID(), workoutServerID: 3,
            workoutName: "Run", workoutType: .running, startedAt: Date(timeIntervalSince1970: 0), exercises: []
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        object.removeValue(forKey: "activity")
        let decoded = try JSONDecoder().decode(ActiveWorkoutSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.activity, .running)
        XCTAssertTrue(decoded.tracksDistance)
    }

    func testAMatchWithATimeCountsAsTrainingAndALiftingDayWithoutSetsDoesNot() {
        XCTAssertTrue(SessionTraining.recordedSomething(activity: .tennis, loggedSetCount: 0, durationSeconds: 3600, distanceKilometers: nil))
        XCTAssertTrue(SessionTraining.recordedSomething(activity: .running, loggedSetCount: 0, durationSeconds: nil, distanceKilometers: 5))
        XCTAssertFalse(
            SessionTraining.recordedSomething(activity: .weightlifting, loggedSetCount: 0, durationSeconds: 3600, distanceKilometers: nil),
            "Sitting in a lifting session is not a workout"
        )
        XCTAssertTrue(SessionTraining.recordedSomething(activity: .calisthenics, loggedSetCount: 2, durationSeconds: nil, distanceKilometers: nil))
        XCTAssertFalse(SessionTraining.recordedSomething(activity: nil, loggedSetCount: 0, durationSeconds: 60, distanceKilometers: nil))
        XCTAssertFalse(SessionTraining.recordedSomething(activity: .yoga, loggedSetCount: 0, durationSeconds: 0, distanceKilometers: nil))
    }

    // MARK: - Effort

    func testEffortBandsMatchTheChartsColumns() {
        let expectations: [(Int, EffortLevel)] = [
            (-5, .veryLight), (0, .veryLight), (1, .veryLight), (20, .veryLight), (21, .light), (40, .light),
            (41, .moderate), (60, .moderate), (61, .hard), (80, .hard), (81, .allOut), (100, .allOut), (150, .allOut),
        ]
        for (score, level) in expectations {
            XCTAssertEqual(EffortLevel(score: score), level, "\(score)")
        }
        XCTAssertEqual(EffortLevel.allCases.map(\.range), [0...20, 20...40, 40...60, 60...80, 80...100])
    }

    // MARK: - Logging after the fact

    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func tennis() -> ActivityLogDraft {
        var draft = ActivityLogDraft(activity: .tennis, endedAt: now)
        draft.hours = "1"
        draft.minutes = "15"
        return draft
    }

    func testOnlyTheTimeIsRequired() throws {
        let entry = try tennis().validated(now: now).get()
        XCTAssertEqual(entry.durationSeconds, 4500)
        XCTAssertEqual(entry.startedAt, now.addingTimeInterval(-4500))
        XCTAssertEqual(entry.workoutName, WorkoutActivity.tennis.title)
        XCTAssertNil(entry.perceivedEffort)
        XCTAssertNil(entry.caloriesKilocalories)
        XCTAssertNil(entry.distanceKilometers)
        XCTAssertTrue(entry.details.isEmpty)
        XCTAssertEqual(entry.notes, "")
    }

    func testTheTimeIsCheckedBeforeAnythingElse() {
        var draft = ActivityLogDraft(activity: .tennis, endedAt: now)
        XCTAssertEqual(draft.validated(now: now).problem, .missingDuration)
        draft.minutes = "0"
        XCTAssertEqual(draft.validated(now: now).problem, .missingDuration)
        draft.hours = "24"
        draft.minutes = "1"
        XCTAssertEqual(draft.validated(now: now).problem, .durationOutOfRange)
        draft.hours = "24"
        draft.minutes = "0"
        XCTAssertNil(draft.validated(now: now).problem)
        draft.endedAt = now.addingTimeInterval(3600)
        XCTAssertEqual(draft.validated(now: now).problem, .startsInFuture)
        draft.endedAt = now.addingTimeInterval(120)
        XCTAssertNil(draft.validated(now: now).problem, "A phone clock a little ahead is allowed for")
    }

    func testCaloriesAreTheirOwnWholeNumberWithinLimits() throws {
        var draft = tennis()
        for bad in ["0", "20001", "12a"] {
            draft.calories = bad
            XCTAssertEqual(draft.validated(now: now).problem, .invalidCalories, bad)
        }
        draft.calories = " 540 "
        XCTAssertEqual(try draft.validated(now: now).get().caloriesKilocalories, 540)
    }

    func testDistanceIsStoredInKilometresWhicheverUnitItWasTypedIn() throws {
        var draft = ActivityLogDraft(activity: .running, endedAt: now)
        draft.minutes = "30"
        draft.distance = "3,1"
        draft.distanceUnit = .miles
        XCTAssertEqual(try draft.validated(now: now).get().distanceKilometers, Decimal(string: "4.989"))
        draft.distanceUnit = .kilometers
        draft.distance = "5"
        XCTAssertEqual(try draft.validated(now: now).get().distanceKilometers, 5)
        XCTAssertTrue(draft.paceOrSpeedText?.contains("6:00") == true, "5 km in 30 minutes is 6:00 per km")
        for bad in ["abc", "0", "-2", "0.001"] {
            draft.distance = bad
            XCTAssertEqual(draft.validated(now: now).problem, .invalidDistance, bad)
        }
        draft.distance = ""
        XCTAssertNil(try draft.validated(now: now).get().distanceKilometers)
    }

    func testAnActivityWithNoDistanceNeverSendsOne() throws {
        var draft = tennis()
        draft.distance = "4"
        XCTAssertNil(try draft.validated(now: now).get().distanceKilometers)
    }

    func testSwitchingActivitiesKeepsOnlyWhatStillApplies() {
        var draft = ActivityLogDraft(activity: .yoga, endedAt: now)
        draft.details[.style] = .text("vinyasa")
        draft.perceivedEffort = 40
        draft.distance = "2"
        draft.notes = "Good class"
        let tennis = draft.switching(to: .tennis)
        XCTAssertTrue(tennis.details.isEmpty, "A yoga style is not a tennis session type")
        XCTAssertEqual(tennis.perceivedEffort, 40)
        XCTAssertEqual(tennis.notes, "Good class")
        XCTAssertEqual(tennis.distance, "", "Tennis does not ask for a distance")
        XCTAssertEqual(draft.switching(to: .soccer).distance, "2", "Soccer does, optionally")
    }

    func testDetailsSendOnlyKnownKeysWithinTheirLimits() throws {
        var details = ActivityDetails()
        details[.rounds] = .integer(5)
        details[.format] = .text("amrap")
        details[.reps] = .integer(10_000)
        details[.movements] = .text("  Thrusters, pull-ups  ")
        details[.sessionType] = .text("match")
        let sanitized = details.sanitized(for: .crossfit)
        XCTAssertEqual(sanitized.integer(.rounds), 5)
        XCTAssertEqual(sanitized.text(.format), "amrap")
        XCTAssertNil(sanitized.integer(.reps), "Out of range is dropped, not clamped into a different answer")
        XCTAssertEqual(sanitized.text(.movements), "Thrusters, pull-ups")
        XCTAssertNil(sanitized.text(.sessionType), "CrossFit does not ask for a session type")

        var style = ActivityDetails()
        style[.style] = .text("reformer")
        XCTAssertTrue(style.sanitized(for: .yoga).isEmpty, "Reformer is a pilates style, not a yoga one")
        XCTAssertEqual(style.sanitized(for: .pilates).text(.style), "reformer")
    }

    func testDetailsTravelAsAPlainJSONObject() throws {
        var details = ActivityDetails()
        details[.sessionType] = .text("match")
        details[.rounds] = .integer(3)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(details)) as? [String: Any]
        XCTAssertEqual(json?["session_type"] as? String, "match")
        XCTAssertEqual(json?["rounds"] as? Int, 3)
        let decoded = try JSONDecoder().decode(ActivityDetails.self, from: Data(#"{"pool_length_m":25}"#.utf8))
        XCTAssertEqual(decoded.integer(.poolLength), 25)
    }

    func testANameLeftBlankIsTheActivitysOwnAndALongOneIsRefused() {
        var draft = tennis()
        draft.name = "   "
        XCTAssertEqual(draft.displayName, WorkoutActivity.tennis.title)
        draft.name = String(repeating: "a", count: 151)
        XCTAssertEqual(draft.validated(now: now).problem, .nameTooLong)
        draft.name = "Sunday doubles"
        XCTAssertEqual(try draft.validated(now: now).get().workoutName, "Sunday doubles")
    }

    // MARK: - Rest timer with the phone locked

    /// The reported case: rests over a minute misbehaving with the phone
    /// locked. Locked means nothing runs, so this checks the timer at the
    /// moments the app could next look -- whenever that is -- for short and
    /// long rests alike, and that "over" happens once and stays over.
    func testRestsOfAnyLengthAreRightWheneverTheAppNextLooks() {
        let start = Date(timeIntervalSince1970: 5_000)
        for length in [30.0, 60, 90, 150, 300, 600] {
            let timer = RestTimer.start(seconds: length, exerciseID: nil, at: start)
            for elapsed in stride(from: 0.0, through: length + 900, by: 7) {
                let now = start.addingTimeInterval(elapsed)
                XCTAssertEqual(timer.remaining(at: now), max(0, length - elapsed), accuracy: 0.001, "\(length)s rest at \(elapsed)s")
                XCTAssertEqual(timer.phase(at: now), elapsed < length ? .running : .finished, "\(length)s rest at \(elapsed)s")
            }
            XCTAssertEqual(timer.endsAt, start.addingTimeInterval(length), "The Lock Screen counts to this date")
        }
    }
}

private extension Result {
    var problem: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
