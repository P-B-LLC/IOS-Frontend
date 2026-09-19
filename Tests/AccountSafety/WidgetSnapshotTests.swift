import Foundation
import XCTest
@testable import AccountSafety

final class WidgetSnapshotTests: XCTestCase {
    func testPagingReachesEveryTaskIncludingLastPartialPage() {
        let pages = (0..<3).map { WidgetTaskPage(total: 5, size: 2, requested: $0) }
        XCTAssertEqual(pages.flatMap { Array($0.range) }, Array(0..<5))
        XCTAssertEqual(pages.last?.range, 4..<5)
        XCTAssertEqual(pages.first?.count, 3)
    }

    func testPagingClampsAfterDeletionAndHandlesEmptyList() {
        XCTAssertEqual(WidgetTaskPage(total: 3, size: 2, requested: 99).range, 2..<3)
        XCTAssertEqual(WidgetTaskPage(total: 3, size: 2, requested: -1).range, 0..<2)
        XCTAssertEqual(WidgetTaskPage(total: 0, size: 2, requested: 99).range, 0..<0)
        XCTAssertEqual(WidgetTaskPage(total: 8, size: 7, requested: 1).range, 7..<8)
        XCTAssertEqual(WidgetTaskPage(total: 3, size: 1, requested: 2).range, 2..<3)
    }

    func testYesterdayIsNeverPresentedAsToday() throws {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let value = WidgetSnapshot(updatedAt: yesterday, day: WidgetSnapshot.dayKey(yesterday), tasks: [], nutrition: nil)
        XCTAssertFalse(value.isCurrent(at: now))
    }

    func testUnknownDataIsDifferentFromAnEmptyPlan() throws {
        let unknown = WidgetSnapshot(updatedAt: .now, day: "2026-09-19", tasks: nil, nutrition: nil)
        let empty = WidgetSnapshot(updatedAt: unknown.updatedAt, day: unknown.day, tasks: [], nutrition: nil)
        XCTAssertNotEqual(unknown, empty)
        XCTAssertNil(try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(unknown)).tasks)
    }

    func testProgressHandlesZeroGoalsAndOverGoalTotals() {
        XCTAssertEqual(WidgetSnapshot.progress(50, toward: 0), 0)
        XCTAssertEqual(WidgetSnapshot.progress(50, toward: -10), 0)
        XCTAssertEqual(WidgetSnapshot.progress(-50, toward: 100), 0)
        XCTAssertEqual(WidgetSnapshot.progress(150, toward: 100), 1)
        XCTAssertEqual(WidgetSnapshot.progress(25, toward: 100), 0.25)
    }

    func testDateKeyUsesGregorianAndSuppliedTimezone() {
        let date = ISO8601DateFormatter().date(from: "2026-09-20T01:00:00Z")!
        XCTAssertEqual(WidgetSnapshot.dayKey(date, timeZone: TimeZone(secondsFromGMT: -18000)!), "2026-09-19")
        XCTAssertEqual(WidgetSnapshot.dayKey(date, timeZone: TimeZone(secondsFromGMT: 0)!), "2026-09-20")
    }

    func testReadRejectsCorruptAndClearedSnapshots() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(WidgetSnapshot.read(from: url))
        try Data("not json".utf8).write(to: url)
        XCTAssertNil(WidgetSnapshot.read(from: url))
        try Data().write(to: url)
        XCTAssertNil(WidgetSnapshot.read(from: url))
    }

    func testCurrentSnapshotRoundTripPreservesSubtaskCounts() throws {
        let now = Date()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let value = WidgetSnapshot(updatedAt: now, day: WidgetSnapshot.dayKey(now), tasks: [
            .init(title: "Pack gym bag", complete: false, workout: false, completable: true, stepsDone: 1, stepsTotal: 2)
        ], nutrition: nil)
        try JSONEncoder().encode(value).write(to: url)
        XCTAssertEqual(WidgetSnapshot.read(from: url, now: now), value)
        XCTAssertNil(WidgetSnapshot.read(from: url, now: now.addingTimeInterval(-60)))
    }
}
