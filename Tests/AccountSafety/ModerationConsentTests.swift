import Foundation
import XCTest

@testable import AccountSafety

/// The question is asked one submission at a time.
///
/// It used to refuse instead. A second submission arriving while a dialog was
/// up hit an `isPresenting` guard and threw, so somebody was told "Nothing was
/// submitted. Safety-review permission is required" having never been asked
/// for it -- the wording blamed them for withholding something nobody offered.
/// Posting a photo while a comment was still in flight was enough.
///
/// There is no window here to put a dialog in, which is exactly why the
/// question is injectable: the ordering is the part worth testing, and it is
/// the part that looks obviously right and is not.
@MainActor
private final class Asker {
    private(set) var calls = 0
    let firstAsked = XCTestExpectation(description: "first submission asked")
    var onSecondAsk: (() -> Void)?
    private var gate: CheckedContinuation<Void, Never>?
    private var answers: [Bool?]

    init(answers: [Bool?]) { self.answers = answers }

    func ask() async -> Bool? {
        calls += 1
        if calls == 1 {
            firstAsked.fulfill()
            // Held open, so the second arrives while this one is still up --
            // the situation the old guard turned into a refusal.
            await withCheckedContinuation { gate = $0 }
        } else if calls == 2 {
            onSecondAsk?()
        }
        return answers.isEmpty ? nil : answers.removeFirst()
    }

    func releaseFirst() {
        gate?.resume()
        gate = nil
    }
}

@MainActor
final class ModerationConsentTests: XCTestCase {
    override func tearDown() async throws {
        // Static, so it would otherwise outlive the test that set it.
        ModerationConsent.askForPermission = { nil }
    }

    func testASecondSubmissionWaitsRatherThanBeingRefused() async throws {
        let asker = Asker(answers: [true, true])
        ModerationConsent.askForPermission = { await asker.ask() }

        async let first: Void = ModerationConsent.require()
        await fulfillment(of: [asker.firstAsked], timeout: 2)

        async let second: Void = ModerationConsent.require()
        let askedEarly = expectation(description: "second asked while the first dialog is up")
        askedEarly.isInverted = true
        asker.onSecondAsk = { askedEarly.fulfill() }
        await fulfillment(of: [askedEarly], timeout: 0.3)
        XCTAssertEqual(asker.calls, 1, "the second must queue behind the first")

        asker.releaseFirst()
        try await first
        try await second
        XCTAssertEqual(asker.calls, 2, "both were asked; neither was refused unasked")
    }

    func testDecliningIsNotTheSameAsBeingUnableToAsk() async {
        // The stores silence one and show the other, so a submission that
        // never happened for a reason nobody chose is not swallowed with the
        // ones somebody cancelled on purpose.
        ModerationConsent.askForPermission = { false }
        do {
            try await ModerationConsent.require()
            XCTFail("declining must stop the submission")
        } catch is ModerationConsent.NotGranted {
        } catch {
            XCTFail("a decline must be NotGranted, got \(error)")
        }

        ModerationConsent.askForPermission = { nil }
        do {
            try await ModerationConsent.require()
            XCTFail("a submission must not go out when the question could not be put")
        } catch is ModerationConsent.CannotAsk {
        } catch {
            XCTFail("an unaskable question must be CannotAsk, got \(error)")
        }
    }

    func testPermissionLetsTheSubmissionThrough() async throws {
        ModerationConsent.askForPermission = { true }
        try await ModerationConsent.require()
    }
}
