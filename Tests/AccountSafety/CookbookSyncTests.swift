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

    func testOverlappingWritesRejectEveryRefreshUntilTheLastOneFinishes() {
        // The store marks a write when it starts and again when it ends. A
        // recipe delete is not serialised behind isSaving, so two can overlap.
        var gate = CookbookSyncGate()
        gate.wrote() // rename starts
        gate.wrote() // recipe delete starts
        let duringBoth = gate.beginRead()
        gate.wrote() // rename ends
        XCTAssertFalse(gate.accepts(duringBoth))
        let duringDelete = gate.beginRead()
        gate.wrote() // recipe delete ends
        XCTAssertFalse(gate.accepts(duringDelete))
        let settled = gate.beginRead()
        XCTAssertTrue(gate.accepts(settled))
    }

    func testCheckingARefreshDoesNotConsumeIt() {
        // A refresh checks once after its requests and again on its error path.
        var gate = CookbookSyncGate()
        let read = gate.beginRead()
        XCTAssertTrue(gate.accepts(read))
        XCTAssertTrue(gate.accepts(read))
    }

    func testRandomInterleavingsAcceptOnlyTheNewestRefreshWithNoWriteSinceItBegan() {
        var random = SplitMix64(seed: 0xC00C_B00C)
        for _ in 0..<500 {
            var gate = CookbookSyncGate()
            var reads: [(read: CookbookSyncGate.Read, superseded: Bool)] = []
            for _ in 0..<24 {
                // Either a write or a newer refresh outdates every earlier refresh.
                for index in reads.indices { reads[index].superseded = true }
                if random.next() % 3 == 0 {
                    gate.wrote()
                } else {
                    reads.append((gate.beginRead(), false))
                }
            }
            for (read, superseded) in reads {
                XCTAssertEqual(gate.accepts(read), !superseded)
            }
        }
    }
}

/// Deterministic, so a failing interleaving reproduces on every run.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
