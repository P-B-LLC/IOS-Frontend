import XCTest
@testable import AccountSafety

/// The welcome guide's rules: who is shown what, when it opens by itself,
/// and how moving through it behaves at either end.
///
/// The overlay that draws it cannot be tapped from here, so the decisions it
/// makes live in AppGuide.swift, beside the routing they lean on.
final class AppGuideTests: XCTestCase {
    func testAnOrdinaryAccountVisitsEveryTabAndNothingItCannotOpen() {
        let steps = AppGuide.steps(for: AppGuideAccess())
        XCTAssertEqual(
            steps.map(\.id),
            ["welcome", "home", "training", "calendar", "social", "account", "done"]
        )
        let lit = steps.filter(\.highlightsTab).map(\.tab)
        XCTAssertEqual(
            Set(lit), Set(RepbaseTab.allCases),
            "every tab in the bar is lit once, so the tour is the whole layout"
        )
    }

    func testAModeratorIsShownTheDashboardInPlace() {
        let steps = AppGuide.steps(for: AppGuideAccess(moderate: true))
        XCTAssertEqual(steps.map(\.id).suffix(3), ["account", "moderation", "done"])
        XCTAssertEqual(steps.first { $0.id == "moderation" }?.tab, .account)
    }

    func testTheTourStartsAndEndsOnACardOfItsOwn() {
        for access in [AppGuideAccess(), AppGuideAccess(moderate: true)] {
            let steps = AppGuide.steps(for: access)
            XCTAssertFalse(steps.first!.highlightsTab)
            XCTAssertFalse(steps.last!.highlightsTab)
            XCTAssertEqual(steps.last!.tab, .home, "it ends where somebody starts")
        }
        XCTAssertEqual(Set(AppGuide.steps.map(\.id)).count, AppGuide.steps.count)
    }

    func testEveryStepIsShortEnoughToReadAtAGlance() {
        for step in AppGuide.steps {
            XCTAssertLessThanOrEqual(step.title.count, 40, step.id)
            XCTAssertLessThanOrEqual(step.body.count, 160, step.id)
        }
    }

    func testItOpensByItselfOnlyForAnAccountThatHasNeverSeenIt() {
        XCTAssertTrue(AppGuide.opensByItself(server: false, seenHere: false, justRegistered: false))
        XCTAssertFalse(AppGuide.opensByItself(server: true, seenHere: false, justRegistered: false))
        XCTAssertFalse(
            AppGuide.opensByItself(server: true, seenHere: false, justRegistered: true),
            "the server knows best when it can be asked"
        )
        XCTAssertFalse(
            AppGuide.opensByItself(server: false, seenHere: true, justRegistered: true),
            "finished on this phone, whether or not the server heard"
        )
    }

    func testNotKnowingIsANoExceptForAnAccountMadeAMomentAgo() {
        // An older server without the endpoint, or no connection.
        XCTAssertFalse(AppGuide.opensByItself(server: nil, seenHere: false, justRegistered: false))
        XCTAssertTrue(AppGuide.opensByItself(server: nil, seenHere: false, justRegistered: true))
    }

    func testWhatIsRememberedIsKeptPerAccountAndPerServer() {
        let origin = "https://rytivo.app"
        XCTAssertNotEqual(
            AppGuide.seenKey(accountID: 1, origin: origin),
            AppGuide.seenKey(accountID: 2, origin: origin)
        )
        XCTAssertNotEqual(
            AppGuide.seenKey(accountID: 1, origin: origin),
            AppGuide.seenKey(accountID: 1, origin: "http://127.0.0.1:8000")
        )
        XCTAssertNotEqual(
            AppGuide.seenKey(accountID: 1, origin: origin),
            AppGuide.tipsKey(accountID: 1, origin: origin)
        )
    }

    func testMovingThroughStopsAtEitherEnd() {
        var progress = AppGuideProgress(steps: AppGuide.steps(for: AppGuideAccess()))
        XCTAssertTrue(progress.isFirst)
        XCTAssertEqual(progress.position, "Step 1 of 7")
        progress.back()
        XCTAssertEqual(progress.index, 0, "Back on the first step goes nowhere")

        for _ in 0..<20 { progress.next() }
        XCTAssertTrue(progress.isLast)
        XCTAssertEqual(progress.step.id, "done")
        XCTAssertEqual(progress.fraction, 1)

        progress.back()
        XCTAssertEqual(progress.step.id, "account")
        XCTAssertFalse(progress.isLast)
    }

    func testEveryTipHasSomethingToSay() {
        for tip in AppGuideTip.allCases {
            XCTAssertFalse(tip.text.isEmpty, tip.rawValue)
            XCTAssertLessThanOrEqual(tip.text.count, 160, tip.rawValue)
        }
    }
}
