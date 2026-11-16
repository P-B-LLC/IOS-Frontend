import Foundation
import XCTest
@testable import AccountSafety

/// Which clip plays, which is got ready, and when neither.
final class FeedPlaybackPolicyTests: XCTestCase {
    private let on = FeedPlaybackSettings()

    private func clips(_ fractions: (Int, Double)...) -> [FeedClip] {
        fractions.map { FeedClip(postID: $0.0, visibleFraction: $0.1) }
    }

    private func plan(
        _ clips: [FeedClip], current: Int? = nil, startedByReader: Int? = nil,
        settings: FeedPlaybackSettings? = nil, rapid: Bool = false, active: Bool = true
    ) -> FeedPlaybackPlan {
        FeedPlaybackPolicy.plan(
            clips: clips, current: current, startedByReader: startedByReader,
            settings: settings ?? on, isScrollingRapidly: rapid, isFeedActive: active
        )
    }

    func testTheCardMostOnScreenPlaysAndOnlyThatOne() {
        let result = plan(clips((1, 0.3), (2, 0.9), (3, 0.7)))
        XCTAssertEqual(result.active, 2)
    }

    func testACardUnderSixtyPercentNeverPlays() {
        XCTAssertNil(plan(clips((1, 0.59), (2, 0.4))).active)
        XCTAssertEqual(plan(clips((1, 0.6))).active, 1)
        XCTAssertEqual(FeedPlaybackPolicy.playableFraction, AttentionMeter.visibleFraction,
                       "what plays is always what is being measured")
    }

    func testATieGoesToTheTopCardAndThePlayingOneKeepsPlaying() {
        let tied = clips((1, 1.0), (2, 1.0))
        XCTAssertEqual(plan(tied).active, 1)
        XCTAssertEqual(plan(tied, current: 2).active, 2, "no swapping back and forth")
    }

    func testOnlyTheNextClipIsPrepared() {
        let result = plan(clips((1, 1.0), (2, 0.2), (3, 0.0), (4, 0.0)))
        XCTAssertEqual(result, FeedPlaybackPlan(active: 1, prepared: 2))
        XCTAssertNil(plan(clips((1, 1.0))).prepared, "nothing below it")
    }

    func testRapidScrollingPreparesNothingAndStartsNothingNew() {
        let passing = clips((1, 0.2), (2, 0.9), (3, 0.6))
        XCTAssertEqual(plan(passing, rapid: true), FeedPlaybackPlan(active: nil, prepared: nil))
        // What was already playing carries on while it is still eligible.
        XCTAssertEqual(plan(passing, current: 3, rapid: true), FeedPlaybackPlan(active: 3, prepared: nil))
        // And stops once it is not.
        XCTAssertNil(plan(clips((3, 0.5), (4, 0.9)), current: 3, rapid: true).active)
        XCTAssertTrue(FeedPlaybackPolicy.isRapid(pointsPerSecond: -1600))
        XCTAssertFalse(FeedPlaybackPolicy.isRapid(pointsPerSecond: 900))
    }

    func testWhenScrollingSettlesTheBestCardStartsAndTheNextIsPrepared() {
        let settled = clips((2, 0.9), (3, 0.6), (4, 0.0))
        XCTAssertEqual(plan(settled), FeedPlaybackPlan(active: 2, prepared: 3))
    }

    func testReduceMotionDataSavingAndTheReadersChoiceEachStopAutoplayAndPreparing() {
        let visible = clips((1, 1.0), (2, 0.3))
        for settings in [
            FeedPlaybackSettings(reduceMotion: true),
            FeedPlaybackSettings(isSavingData: true),
            FeedPlaybackSettings(autoplayPreferred: false),
        ] {
            XCTAssertEqual(plan(visible, settings: settings), FeedPlaybackPlan(active: nil, prepared: nil))
        }
    }

    func testAClipTheReaderStartedPlaysWhateverTheSettingsAndStaysTheOne() {
        let off = FeedPlaybackSettings(autoplayPreferred: false, isSavingData: true)
        let visible = clips((1, 1.0), (2, 0.7))
        let result = plan(visible, current: 2, startedByReader: 2, settings: off)
        XCTAssertEqual(result, FeedPlaybackPlan(active: 2, prepared: nil), "played, and nothing prepared behind it")
        XCTAssertEqual(plan(visible, startedByReader: 2).active, 2, "over a more visible card")
        XCTAssertNil(plan(clips((1, 1.0), (2, 0.4)), startedByReader: 2, settings: off).active,
                     "until it leaves the screen")
    }

    func testCoveredOrBackgroundedNothingPlaysOrIsPrepared() {
        XCTAssertEqual(
            plan(clips((1, 1.0), (2, 0.5)), current: 1, startedByReader: 1, active: false),
            FeedPlaybackPlan(active: nil, prepared: nil)
        )
    }

    func testAnEmptyFeedHasNoPlan() {
        XCTAssertEqual(plan([]), FeedPlaybackPlan(active: nil, prepared: nil))
    }
}
