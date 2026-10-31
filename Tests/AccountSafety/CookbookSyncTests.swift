import XCTest
@testable import AccountSafety

final class CookbookSyncTests: XCTestCase {
    func testRefreshBeforeSaveCannotReplaceConfirmedLibrary() {
        var gate = CookbookSyncGate()
        let old = gate.beginRead()
        gate.wrote()
        XCTAssertFalse(gate.accepts(old))
        let latest = gate.beginRead()
        XCTAssertTrue(gate.accepts(latest))
    }

    func testReorderedResponsesKeepNewestRefresh() {
        var gate = CookbookSyncGate()
        let first = gate.beginRead()
        let second = gate.beginRead()
        XCTAssertTrue(gate.accepts(second))
        XCTAssertFalse(gate.accepts(first))
    }

    func testWriteFinishingAfterRefreshStartedInvalidatesIt() {
        var gate = CookbookSyncGate()
        gate.wrote()
        let duringWrite = gate.beginRead()
        gate.wrote()
        XCTAssertFalse(gate.accepts(duringWrite))
    }
}
