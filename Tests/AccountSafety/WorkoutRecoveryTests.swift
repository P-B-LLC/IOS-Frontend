import Foundation
import XCTest
@testable import AccountSafety

final class WorkoutRecoveryTests: XCTestCase {
    @MainActor func testDiscardedSessionCannotBeReplayedAfterRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let queue = PendingWorkoutSaves(directory: directory, defaults: defaults)
        let entry = PendingWorkoutSave(id: UUID(), ownerID: 1, origin: "test", sessionID: 7,
                                       workoutName: "Run", requestedAt: Date(), points: [])
        try queue.put(entry)
        try queue.discardSession(ownerID: 1, origin: "test", sessionID: 7)
        let relaunched = PendingWorkoutSaves(directory: directory, defaults: defaults)
        XCTAssertTrue(try relaunched.entries(ownerID: 1, origin: "test").isEmpty)
    }

    @MainActor func testQueueSurvivesRelaunchAndSeparatesAccountsAndServers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let queue = PendingWorkoutSaves(directory: directory, defaults: defaults)
        let entry = PendingWorkoutSave(id: UUID(), ownerID: 1, origin: "https://example.invalid/", sessionID: 7,
                                       workoutName: "Run", requestedAt: Date(), points: [
                                        RoutePoint(latitude: 41, longitude: -87, recordedAt: Date())
                                       ])
        try queue.put(entry)
        try queue.put(entry)
        let relaunched = PendingWorkoutSaves(directory: directory, defaults: defaults)
        XCTAssertEqual(try relaunched.entries(ownerID: 1, origin: entry.origin).count, 1)
        XCTAssertEqual(try relaunched.entries(ownerID: 1, origin: entry.origin).first?.points, entry.points)
        XCTAssertTrue(try relaunched.entries(ownerID: 2, origin: entry.origin).isEmpty)
        XCTAssertTrue(try relaunched.entries(ownerID: 1, origin: "https://other.invalid/").isEmpty)
        try relaunched.remove(entry)
        XCTAssertTrue(try queue.entries(ownerID: 1, origin: entry.origin).isEmpty)
    }

    @MainActor func testUnreadableQueueIsNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("pending-workouts.json")
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: file)
        let queue = PendingWorkoutSaves(directory: directory, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let entry = PendingWorkoutSave(id: UUID(), ownerID: 1, origin: "test", sessionID: 1, workoutName: "Run", requestedAt: Date(), points: [])
        XCTAssertThrowsError(try queue.put(entry))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    @MainActor func testDeletionRemovesOnlyTheDeletedAccountsQueue() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingWorkoutSaves(directory: directory, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for owner in [1, 2] {
            try queue.put(PendingWorkoutSave(id: UUID(), ownerID: owner, origin: "test", sessionID: owner, workoutName: "Workout", requestedAt: Date(), points: []))
        }
        try queue.removeAccount(ownerID: 1, origin: "test")
        XCTAssertTrue(try queue.entries(ownerID: 1, origin: "test").isEmpty)
        XCTAssertEqual(try queue.entries(ownerID: 2, origin: "test").count, 1)
    }
}
