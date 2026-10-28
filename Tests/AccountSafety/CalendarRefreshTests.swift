import Foundation
import XCTest
@testable import AccountSafety

/// Responses are released explicitly so race tests do not depend on sleeps.
@MainActor
private final class HeldCalendarRefresh {
    let starts: [XCTestExpectation]
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var calls = 0
    private var active = 0
    private(set) var maximumActive = 0
    private(set) var cancellationAtFinish: [Bool] = []

    init(expectedCalls: Int) {
        starts = (0..<expectedCalls).map { XCTestExpectation(description: "refresh \($0) started") }
    }

    func send() async {
        let index = calls
        calls += 1
        guard index < starts.count else {
            XCTFail("Unexpected extra refresh")
            return
        }
        active += 1
        maximumActive = max(maximumActive, active)
        await withCheckedContinuation { continuation in
            continuations[index] = continuation
            starts[index].fulfill()
        }
        cancellationAtFinish.append(Task.isCancelled)
        active -= 1
    }

    func resolve(_ index: Int) {
        guard let continuation = continuations.removeValue(forKey: index) else {
            XCTFail("Refresh \(index) was not waiting")
            return
        }
        continuation.resume()
    }
}

final class CalendarRefreshTests: XCTestCase {
    private func appSource(_ relativePath: String) throws -> String {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"],
                                 "Run through Scripts/test-account-safety.sh to locate app sources")
        let url = URL(fileURLWithPath: root).appendingPathComponent("IOS Frontend/IOS Frontend/\(relativePath)")
        return try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n")
    }

    private func section(_ source: String, from start: String, to end: String) throws -> String {
        let beginning = try XCTUnwrap(source.range(of: start), "Missing source boundary: \(start)")
        let ending = try XCTUnwrap(source.range(of: end, range: beginning.upperBound..<source.endIndex),
                                   "Missing source boundary: \(end)")
        return String(source[beginning.lowerBound..<ending.lowerBound])
    }

    @MainActor private func wait(_ expectations: [XCTestExpectation]) async {
        let result = await XCTWaiter.fulfillment(of: expectations, timeout: 2)
        XCTAssertEqual(result, .completed, "A held calendar operation never completed")
    }

    @MainActor func testChangeDuringRefreshRunsAgainWithLatestOperationAndState() async {
        let coordinator = CalendarRefreshCoordinator()
        let requests = HeldCalendarRefresh(expectedCalls: 2)
        var serverSchedule = "rotation"
        var displayedSchedule = ""
        var operationUsed = ""
        let first = Task { @MainActor in
            await coordinator.refresh {
                let snapshot = serverSchedule
                await requests.send()
                displayedSchedule = snapshot
                operationUsed = "initial"
            }
        }
        await wait([requests.starts[0]])

        serverSchedule = "manual workout"
        let queued = XCTestExpectation(description: "new calendar notification queued")
        let second = Task { @MainActor in
            queued.fulfill()
            await coordinator.refresh {
                let snapshot = serverSchedule
                await requests.send()
                displayedSchedule = snapshot
                operationUsed = "latest"
            }
        }
        await wait([queued])
        requests.resolve(0)
        await wait([requests.starts[1]])
        requests.resolve(1)
        await first.value
        await second.value

        XCTAssertEqual(requests.calls, 2)
        XCTAssertEqual(requests.maximumActive, 1)
        XCTAssertEqual(displayedSchedule, "manual workout")
        XCTAssertEqual(operationUsed, "latest")
    }

    @MainActor func testRepeatedNotificationsCoalesceIntoOneFollowUpIncludingClear() async {
        let coordinator = CalendarRefreshCoordinator()
        let requests = HeldCalendarRefresh(expectedCalls: 2)
        var serverSchedule = [1, 2, 3]
        var displayedSchedule = [Int]()
        let refresh: @MainActor () async -> Void = {
            let snapshot = serverSchedule
            await requests.send()
            displayedSchedule = snapshot
        }
        let first = Task { @MainActor in await coordinator.refresh(refresh) }
        await wait([requests.starts[0]])

        serverSchedule = []
        let queued = XCTestExpectation(description: "all notifications queued")
        queued.expectedFulfillmentCount = 5
        let followers = (0..<5).map { _ in
            Task { @MainActor in
                queued.fulfill()
                await coordinator.refresh(refresh)
            }
        }
        await wait([queued])
        XCTAssertEqual(requests.calls, 1)
        requests.resolve(0)
        await wait([requests.starts[1]])
        requests.resolve(1)
        await first.value
        for follower in followers { await follower.value }

        XCTAssertEqual(requests.calls, 2)
        XCTAssertEqual(requests.maximumActive, 1)
        XCTAssertTrue(displayedSchedule.isEmpty)
    }

    @MainActor func testCancellingCallerDoesNotCancelSharedWorker() async {
        let coordinator = CalendarRefreshCoordinator()
        let requests = HeldCalendarRefresh(expectedCalls: 1)
        var completions = 0
        let caller = Task { @MainActor in
            await coordinator.refresh {
                await requests.send()
                completions += 1
            }
        }
        await wait([requests.starts[0]])
        caller.cancel()
        requests.resolve(0)
        await caller.value

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(requests.cancellationAtFinish, [false])
        await coordinator.refresh { completions += 1 }
        XCTAssertEqual(completions, 2, "The cancelled caller must not leave the coordinator busy")
    }

    @MainActor func testResetAllowsNewWorkerAndOldCompletionCannotClearIt() async {
        let coordinator = CalendarRefreshCoordinator()
        let oldRequests = HeldCalendarRefresh(expectedCalls: 1)
        let freshRequests = HeldCalendarRefresh(expectedCalls: 2)
        let old = Task { @MainActor in
            await coordinator.refresh { await oldRequests.send() }
        }
        await wait([oldRequests.starts[0]])
        coordinator.reset()

        let fresh = Task { @MainActor in
            await coordinator.refresh { await freshRequests.send() }
        }
        await wait([freshRequests.starts[0]])
        oldRequests.resolve(0)
        await old.value

        let queued = XCTestExpectation(description: "new account follow-up queued")
        let followUp = Task { @MainActor in
            queued.fulfill()
            await coordinator.refresh { await freshRequests.send() }
        }
        await wait([queued])
        XCTAssertEqual(freshRequests.calls, 1)
        freshRequests.resolve(0)
        await wait([freshRequests.starts[1]])
        freshRequests.resolve(1)
        await fresh.value
        await followUp.value

        XCTAssertEqual(oldRequests.cancellationAtFinish, [true])
        XCTAssertEqual(freshRequests.calls, 2)
        XCTAssertEqual(freshRequests.maximumActive, 1)
        XCTAssertEqual(freshRequests.cancellationAtFinish, [false, false])
    }

    @MainActor func testReadGateRejectsSnapshotsBeforeMutationAndNewerRead() {
        let reads = CalendarReadGate()
        let beforeClear = reads.begin()
        XCTAssertTrue(reads.accepts(beforeClear))
        reads.invalidate()
        XCTAssertFalse(reads.accepts(beforeClear))

        let afterClear = reads.begin()
        XCTAssertFalse(reads.accepts(beforeClear))
        XCTAssertTrue(reads.accepts(afterClear))
        let afterNewWorkout = reads.begin()
        XCTAssertFalse(reads.accepts(afterClear))
        XCTAssertTrue(reads.accepts(afterNewWorkout))
        reads.invalidate()
        XCTAssertFalse(reads.accepts(afterNewWorkout), "Account reset must reject old snapshots too")
    }

    func testAppObservesCalendarRevisionRatherThanOnlyCurrentWeekContents() throws {
        let app = try appSource("IOS_FrontendApp.swift")
        XCTAssertTrue(app.contains(".task(id: workoutStore.calendarRevision)"))
        XCTAssertFalse(app.contains(".task(id: workoutStore.currentWeekWorkouts)"),
                       "Identical or empty current weeks can still mean deleted future rotation days")
        XCTAssertGreaterThanOrEqual(app.components(separatedBy: "await plannerStore.refreshScheduledWorkouts()").count - 1, 2,
                                    "Both startup and calendar revisions must reconcile planner snapshots")
        let cycleCallback = try section(app, from: "cycleStore.onCalendarChanged =", to: "await cycleStore.connect(")
        XCTAssertTrue(cycleCallback.contains("await workoutStore.reloadSchedule()"))
    }

    func testPlannerRefreshIsAuthoritativeEvenForAnEmptySchedule() throws {
        let planner = try appSource("Stores/PlannerStore.swift")
        let refresh = try section(planner, from: "func refreshScheduledWorkouts()", to: "// MARK: - Navigation")
        XCTAssertTrue(refresh.contains("monthReads.invalidate()"))
        XCTAssertTrue(refresh.contains("await calendarRefresh.refresh"))
        XCTAssertTrue(refresh.contains("await self.reloadMonth(generation: generation, showsLoadingState: false)"))
        XCTAssertFalse(refresh.contains("currentWeekWorkouts"))
        XCTAssertFalse(refresh.contains("dates.first"))
        XCTAssertFalse(refresh.contains("for entry in created"))
        XCTAssertFalse(planner.contains("isSyncingScheduledWorkouts"),
                       "Busy flags that return early lose the newest schedule change")
    }

    func testMonthAndSurroundingsShareTheSameStaleReadGuard() throws {
        let planner = try appSource("Stores/PlannerStore.swift")
        let month = try section(planner, from: "private func reloadMonth(", to: "private func reloadSurroundings(")
        XCTAssertTrue(month.contains("let readID = monthReads.begin()"))
        XCTAssertTrue(month.contains("guard connectionGeneration == generation, monthReads.accepts(readID) else { return }\n            entriesByDate ="))
        XCTAssertTrue(month.contains("await reloadSurroundings(generation: generation, readID: readID)"))
        let surroundings = try section(planner, from: "private func reloadSurroundings(", to: "private func reconcileCompletion(")
        XCTAssertGreaterThanOrEqual(surroundings.components(separatedBy: "monthReads.accepts(readID)").count - 1, 3,
                                    "Entry, success, and failure paths must reject obsolete surrounding reads")
        XCTAssertTrue(surroundings.contains("reminderEntries = loadedRemindable.map { reconcileCompletion($0, read: read) }"))
    }

    func testWorkoutReadsNotifyPlannerEvenWhenThisWeekIsUnchanged() throws {
        let workouts = try appSource("Stores/WorkoutStore.swift")
        XCTAssertTrue(workouts.contains("private(set) var calendarRevision: UInt64"))
        let reload = try section(workouts, from: "private func reloadWeek(", to: "private func sessionExercise(")
        XCTAssertTrue(reload.contains("let readID = scheduleReads.begin()"))
        XCTAssertTrue(reload.contains("calendarRevision &+= 1"))
        XCTAssertGreaterThanOrEqual(reload.components(separatedBy: "scheduleReads.accepts(readID)").count - 1, 3)
        let remove = try section(workouts, from: "func removeWorkout(", to: "func setRepeat(")
        let repeatChange = try section(workouts, from: "func setRepeat(", to: "private func mutateWorkout(")
        for mutation in [remove, repeatChange] {
            XCTAssertTrue(mutation.contains("scheduleReads.invalidate()"))
            XCTAssertTrue(mutation.contains("calendarRevision &+= 1"))
        }
    }
}
