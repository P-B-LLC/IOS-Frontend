import XCTest
@testable import AccountSafety

final class FoodDaySyncTests: XCTestCase {
    @MainActor func testDelayedDayCannotOverwriteConfirmedFood() throws {
        let sync = FoodDaySyncCoordinator()
        let read = try XCTUnwrap(sync.beginRead("day:2026-09-13"))
        var calories = 100
        let write = sync.beginWrite(days: ["2026-09-13"])
        calories = 800
        sync.endWrite(write)
        if sync.accept(read, day: "2026-09-13") { calories = 100 }
        XCTAssertEqual(calories, 800)
    }

    @MainActor func testMonthPreservesSavedDayButAcceptsOtherDays() throws {
        let sync = FoodDaySyncCoordinator()
        let month = try XCTUnwrap(sync.beginRead("month:2026-09-01"))
        let write = sync.beginWrite(days: ["2026-09-13"])
        sync.endWrite(write)
        XCTAssertFalse(sync.accept(month, day: "2026-09-13"))
        XCTAssertTrue(sync.accept(month, day: "2026-09-14"))
    }

    @MainActor func testReadStartedDuringFailedWriteIsRejectedButLaterReadCanRecover() throws {
        let sync = FoodDaySyncCoordinator()
        let write = sync.beginWrite(days: ["day"])
        let during = try XCTUnwrap(sync.beginRead("month:x"))
        XCTAssertFalse(sync.accept(during, day: "day"))
        sync.endWrite(write) // Failed request: do not change confirmed local meals.
        XCTAssertFalse(sync.accept(during, day: "day"))
        let after = try XCTUnwrap(sync.beginRead("day:day"))
        XCTAssertTrue(sync.accept(after, day: "day"))
    }

    @MainActor func testInitialLoadCannotReplaceNewerDayRead() throws {
        let sync = FoodDaySyncCoordinator()
        let initial = try XCTUnwrap(sync.beginRead("initial"))
        let day = try XCTUnwrap(sync.beginRead("day:day"))
        XCTAssertTrue(sync.accept(day, day: "day"))
        sync.endRead(day)
        XCTAssertFalse(sync.accept(initial, day: "day"))
        XCTAssertTrue(sync.accept(initial, day: "other"))
    }

    @MainActor func testDeletionCannotBeResurrectedByDelayedMonth() throws {
        let sync = FoodDaySyncCoordinator()
        let month = try XCTUnwrap(sync.beginRead("month:x"))
        var meals = [1, 2]
        let deletion = sync.beginWrite(days: ["day"])
        meals.removeAll()
        sync.endWrite(deletion)
        if sync.accept(month, day: "day") { meals = [1, 2] }
        XCTAssertTrue(meals.isEmpty)
    }

    @MainActor func testRecipeProtectsAllDatesAndLaterCleanReadsRemainAuthoritative() throws {
        let sync = FoodDaySyncCoordinator()
        let month = try XCTUnwrap(sync.beginRead("month:x"))
        let recipe = sync.beginWrite(days: ["a", "b", "c"])
        sync.endWrite(recipe)
        for day in ["a", "b", "c"] { XCTAssertFalse(sync.accept(month, day: day)) }
        XCTAssertTrue(sync.accept(month, day: "d"))
        let later = try XCTUnwrap(sync.beginRead("month:y"))
        // A fresh server read may remove meals changed on another device.
        for day in ["a", "b", "c"] { XCTAssertTrue(sync.accept(later, day: day)) }
    }

    @MainActor func testDuplicateReadsCoalesceAndFailureReleasesSlot() throws {
        let sync = FoodDaySyncCoordinator()
        let day = try XCTUnwrap(sync.beginRead("day:a"))
        XCTAssertNil(sync.beginRead("day:a"))
        XCTAssertNotNil(sync.beginRead("day:b"))
        XCTAssertTrue(sync.endRead(day)) // Same completion path for failure.
        XCTAssertNotNil(sync.beginRead("day:a"))
        let month = try XCTUnwrap(sync.beginRead("month:a"))
        XCTAssertNil(sync.beginRead("month:a"))
        XCTAssertTrue(sync.hasMonthReads)
        sync.endRead(month)
        XCTAssertFalse(sync.hasMonthReads)
    }

    @MainActor func testOldCompletionCannotReleasePostSaveRefresh() throws {
        let sync = FoodDaySyncCoordinator()
        let old = try XCTUnwrap(sync.beginRead("day:a"))
        let write = sync.beginWrite(days: ["a"])
        sync.endWrite(write)
        let fresh = try XCTUnwrap(sync.beginRead("day:a"))
        XCTAssertFalse(sync.endRead(old))
        XCTAssertTrue(sync.isCurrent(fresh))
        XCTAssertNil(sync.beginRead("day:a"))
        XCTAssertTrue(sync.accept(fresh, day: "a"))
    }

    @MainActor func testAccountResetRejectsOldReadsAndWrites() throws {
        let sync = FoodDaySyncCoordinator()
        let read = try XCTUnwrap(sync.beginRead("month:a"))
        let write = sync.beginWrite(days: ["a"])
        sync.reset()
        let newRead = try XCTUnwrap(sync.beginRead("month:a"))
        let newWrite = sync.beginWrite(days: ["a"])
        XCTAssertFalse(sync.accept(read, day: "b"))
        XCTAssertFalse(sync.endRead(read))
        XCTAssertFalse(sync.endWrite(write))
        XCTAssertTrue(sync.isCurrent(newRead))
        XCTAssertTrue(sync.isWriting("a"))
        XCTAssertTrue(sync.endWrite(newWrite))
    }

    @MainActor func testMonthLoadingStaysActiveUntilEveryMonthFinishes() throws {
        let sync = FoodDaySyncCoordinator()
        let first = try XCTUnwrap(sync.beginRead("month:a"))
        let second = try XCTUnwrap(sync.beginRead("month:b"))
        sync.endRead(second)
        XCTAssertTrue(sync.hasMonthReads)
        sync.endRead(first)
        XCTAssertFalse(sync.hasMonthReads)
    }
}
