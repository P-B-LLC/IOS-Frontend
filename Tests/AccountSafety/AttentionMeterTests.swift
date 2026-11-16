import Foundation
import XCTest
@testable import AccountSafety

/// What a reader gave a post, measured with a clock the test holds.
///
/// Each test is one of the ways the old tracker could be fooled or the new
/// one could over-count: a seek, a loop, a faster speed, buffering, the app
/// leaving, a sheet over the card, a card only partly on screen.
final class AttentionMeterTests: XCTestCase {
    private let wall = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var meter = AttentionMeter()

    override func setUp() {
        meter = AttentionMeter()
    }

    /// Shows a ten-second clip at t=0.
    private func showClip(_ postID: Int = 1, duration: Int = 10_000, at now: TimeInterval = 0) {
        meter.shown(postID, surface: "for_you", at: now)
        meter.hasClip(postID, durationMilliseconds: duration)
    }

    /// Plays from one media position to another at a rate, reporting once a
    /// second as the player does. Returns the time it finished.
    @discardableResult
    private func play(_ postID: Int = 1, from: Double, to: Double, startingAt start: TimeInterval, rate: Double = 1) -> TimeInterval {
        meter.playing(true, postID: postID, positionMilliseconds: from, at: start)
        var now = start, position = from
        while position < to {
            let step = min(1000 * rate, to - position)
            position += step
            now += step / 1000 / rate
            meter.progress(postID, positionMilliseconds: position, at: now)
        }
        return now
    }

    private func end(_ postID: Int = 1, at now: TimeInterval) -> AttentionSummary {
        guard let summary = meter.hidden(postID, at: now, wallClock: wall) else {
            XCTFail("expected a summary"); fatalError()
        }
        return summary
    }

    // MARK: Exposure

    func testAnExposureRunsFromShownToHiddenAndARepeatedShownIsTheSameOne() {
        meter.shown(1, surface: "following", at: 10)
        meter.shown(1, surface: "for_you", at: 11)
        let summary = end(at: 14.2)
        XCTAssertEqual(summary.dwellMilliseconds, 4200)
        XCTAssertEqual(summary.activeDwellMilliseconds, 4200)
        XCTAssertEqual(summary.surface, "following")
        XCTAssertEqual(summary.observedAt, wall)
        XCTAssertNil(meter.hidden(1, at: 20), "hiding what is not exposed reports nothing")
    }

    func testAFlickPastIsNotReportedAndDoesNotUseASequenceNumber() {
        meter.shown(1, surface: "for_you", at: 0)
        XCTAssertNil(meter.hidden(1, at: 0.249))
        meter.shown(2, surface: "for_you", at: 1)
        XCTAssertEqual(end(2, at: 1.25).sequence, 1)
    }

    func testSequenceCountsUpAcrossPosts() {
        for postID in 1...3 {
            meter.shown(postID, surface: "for_you", at: 0)
        }
        XCTAssertEqual(meter.hideAll(at: 5, wallClock: wall).map(\.sequence), [1, 2, 3])
    }

    func testAPhotoReportsNoPlaybackRatherThanNoneWatched() {
        meter.shown(1, surface: "for_you", at: 0)
        // A player event for a post with no clip is ignored.
        meter.playing(true, postID: 1, positionMilliseconds: 0, at: 1)
        let summary = end(at: 3)
        XCTAssertNil(summary.playbackMilliseconds)
        XCTAssertNil(summary.coverageMilliseconds)
        XCTAssertNil(summary.rewatchMilliseconds)
        XCTAssertFalse(summary.completed)
    }

    func testAClockThatWentBackwardsNeverGivesANegativeFigure() {
        showClip(at: 100)
        meter.playing(true, postID: 1, positionMilliseconds: 0, at: 90)
        meter.progress(1, positionMilliseconds: 1000, at: 80)
        XCTAssertNil(meter.hidden(1, at: 50), "a negative dwell is not an exposure")
    }

    func testFiguresAreCappedAtWhatTheServerAccepts() {
        showClip(duration: 30_000)
        meter.playing(true, postID: 1, positionMilliseconds: 0, at: 0)
        let summary = end(at: 3 * 60 * 60)
        XCTAssertEqual(summary.dwellMilliseconds, AttentionMeter.maxMilliseconds)
        XCTAssertEqual(summary.activeDwellMilliseconds, AttentionMeter.maxMilliseconds)
        XCTAssertEqual(summary.playbackMilliseconds, AttentionMeter.maxMilliseconds)
    }

    // MARK: Playback and coverage

    func testPlayingStraightThroughCoversWhatWasPlayed() {
        showClip()
        let stopped = play(from: 0, to: 4000, startingAt: 1)
        meter.playing(false, postID: 1, positionMilliseconds: 4000, at: stopped)
        let summary = end(at: 6)
        XCTAssertEqual(summary.playbackMilliseconds, 4000)
        XCTAssertEqual(summary.coverageMilliseconds, 4000)
        XCTAssertEqual(summary.rewatchMilliseconds, 0)
        XCTAssertFalse(summary.completed)
    }

    func testSeekingForwardCoversNothingInBetween() {
        showClip()
        var now = play(from: 0, to: 1000, startingAt: 0)
        // Dragged to nine seconds, then let play to the end.
        meter.seeked(1, toMilliseconds: 9000, at: now)
        now = play(from: 9000, to: 10_000, startingAt: now)
        meter.ended(1, at: now)
        let summary = end(at: now + 1)
        XCTAssertEqual(summary.coverageMilliseconds, 2000, "one second at each end")
        XCTAssertFalse(summary.completed, "reaching the end is not watching it")
    }

    func testASeekNobodyReportedIsStillNotCoverage() {
        // The player jumps without telling the meter: a report that could
        // not have been reached by playing starts a new stretch.
        showClip()
        meter.playing(true, postID: 1, positionMilliseconds: 0, at: 0)
        meter.progress(1, positionMilliseconds: 1000, at: 1)
        meter.progress(1, positionMilliseconds: 9000, at: 1.2)
        meter.progress(1, positionMilliseconds: 10_000, at: 2.2)
        meter.ended(1, at: 2.2)
        let summary = end(at: 3)
        XCTAssertEqual(summary.coverageMilliseconds, 2000)
        XCTAssertFalse(summary.completed)
    }

    func testSeekingBackAndWatchingAgainIsRewatchNotMoreCoverage() {
        showClip()
        var now = play(from: 0, to: 4000, startingAt: 0)
        meter.seeked(1, toMilliseconds: 1000, at: now)
        now = play(from: 1000, to: 5000, startingAt: now)
        let summary = end(at: now)
        XCTAssertEqual(summary.coverageMilliseconds, 5000)
        XCTAssertEqual(summary.rewatchMilliseconds, 3000)
        XCTAssertEqual(summary.playbackMilliseconds, 8000)
    }

    func testAClipThatLoopsIsCoveredOnceAndTheRestIsRewatch() {
        showClip(duration: 2000)
        var now: TimeInterval = 0
        for _ in 0..<5 {
            now = play(from: 0, to: 2000, startingAt: now)
            meter.ended(1, at: now)
        }
        let summary = end(at: now)
        XCTAssertEqual(summary.coverageMilliseconds, 2000)
        XCTAssertEqual(summary.rewatchMilliseconds, 8000)
        XCTAssertTrue(summary.completed)
    }

    func testWatchedThroughNeedsANaturalEndAndNineTenthsCovered() {
        // Skipped the first 0.9 s of ten: 91% covered, and it ended.
        showClip(1)
        var now = play(1, from: 900, to: 10_000, startingAt: 0)
        meter.ended(1, at: now)
        XCTAssertTrue(end(1, at: now).completed)

        // Skipped the first 1.1 s: 89%.
        showClip(2, at: 100)
        now = play(2, from: 1100, to: 10_000, startingAt: 100)
        meter.ended(2, at: now)
        XCTAssertFalse(end(2, at: now).completed)

        // All of it covered, but scrolled away a moment before the end.
        showClip(3, at: 200)
        now = play(3, from: 0, to: 9900, startingAt: 200)
        XCTAssertFalse(end(3, at: now).completed)
    }

    func testAtDoubleSpeedTheClipIsCoveredInHalfTheTime() {
        showClip()
        let now = play(from: 0, to: 10_000, startingAt: 0, rate: 2)
        meter.ended(1, at: now)
        let summary = end(at: now)
        XCTAssertEqual(summary.playbackMilliseconds, 5000, "wall time spent playing")
        XCTAssertEqual(summary.coverageMilliseconds, 10_000, "media time covered")
        XCTAssertTrue(summary.completed)
    }

    func testBufferingAndPausingAreNotPlayback() {
        showClip()
        var now = play(from: 0, to: 2000, startingAt: 0)
        // Stalls for five seconds, then carries on.
        meter.playing(false, postID: 1, positionMilliseconds: 2000, at: now)
        now += 5
        now = play(from: 2000, to: 3000, startingAt: now)
        // Paused by the reader for ten.
        meter.playing(false, postID: 1, positionMilliseconds: 3000, at: now)
        now += 10
        let summary = end(at: now)
        XCTAssertEqual(summary.playbackMilliseconds, 3000)
        XCTAssertEqual(summary.coverageMilliseconds, 3000)
        XCTAssertEqual(summary.activeDwellMilliseconds, 18_000, "still looking at the card")
    }

    func testAStalledClockDoesNotTurnAStallIntoCoverage() {
        // The player reports "playing" but the position does not move.
        showClip()
        meter.playing(true, postID: 1, positionMilliseconds: 1000, at: 0)
        meter.progress(1, positionMilliseconds: 1000, at: 4)
        XCTAssertEqual(end(at: 4).coverageMilliseconds, 0)
    }

    func testAClipThatCouldNotPlaySaysSo() {
        showClip()
        meter.failed(1, at: 0.4)
        let summary = end(at: 0.6)
        XCTAssertTrue(summary.playbackFailed)
        XCTAssertEqual(summary.playbackMilliseconds, 0)
        XCTAssertEqual(summary.coverageMilliseconds, 0)
    }

    // MARK: What stops the clocks

    func testTheAppLeavingStopsTheClocksAndTheClipIsNotWatchedMeanwhile() {
        showClip()
        var now = play(from: 0, to: 2000, startingAt: 0)
        meter.appBecameActive(false, at: now)
        // A minute in the background. The player may carry on reporting.
        meter.progress(1, positionMilliseconds: 3000, at: now + 1)
        now += 60
        meter.appBecameActive(true, at: now)
        meter.progress(1, positionMilliseconds: 8000, at: now + 0.1)
        now = play(from: 8000, to: 9000, startingAt: now + 0.1)
        let summary = end(at: now)
        XCTAssertEqual(summary.playbackMilliseconds, 3100)
        XCTAssertEqual(summary.coverageMilliseconds, 3000, "two seconds before, one after")
        XCTAssertEqual(summary.activeDwellMilliseconds, 3100)
        XCTAssertEqual(summary.dwellMilliseconds, 63_100)
    }

    func testASheetOverTheFeedSuspendsTheCardWithoutEndingTheExposure() {
        showClip()
        var now = play(from: 0, to: 2000, startingAt: 0)
        meter.feedCovered(true, at: now)
        now += 30
        meter.feedCovered(false, at: now)
        now = play(from: 2000, to: 4000, startingAt: now)
        let summary = end(at: now)
        XCTAssertEqual(summary.sequence, 1, "one exposure, with a gap in it")
        XCTAssertEqual(summary.activeDwellMilliseconds, 4000)
        XCTAssertEqual(summary.playbackMilliseconds, 4000)
        XCTAssertEqual(summary.coverageMilliseconds, 4000)
        XCTAssertEqual(summary.dwellMilliseconds, 34_000)
    }

    func testSheetsStackAndTheCardWaitsForTheLastToGo() {
        meter.shown(1, surface: "for_you", at: 0)
        meter.feedCovered(true, at: 1)
        meter.feedCovered(true, at: 2)
        meter.feedCovered(false, at: 3)
        XCTAssertEqual(meter.hidden(1, at: 4)?.activeDwellMilliseconds, 1000, "still covered")
        meter.shown(2, surface: "for_you", at: 4)
        meter.feedCovered(false, at: 5)
        meter.feedCovered(false, at: 6)
        XCTAssertEqual(meter.hidden(2, at: 7)?.activeDwellMilliseconds, 2000)
    }

    func testACardShownWhileTheFeedIsCoveredIsNotActiveUntilItIsUncovered() {
        meter.feedCovered(true, at: 0)
        meter.shown(1, surface: "for_you", at: 0)
        meter.feedCovered(false, at: 3)
        let summary = end(at: 5)
        XCTAssertEqual(summary.dwellMilliseconds, 5000)
        XCTAssertEqual(summary.activeDwellMilliseconds, 2000)
    }

    func testOpeningTheAttachmentIsReadingAndPausesThePost() {
        showClip()
        var now = play(from: 0, to: 1000, startingAt: 0)
        meter.attachmentOpened(1, at: now)
        meter.feedCovered(true, at: now)
        now += 20
        meter.attachmentClosed(1, at: now)
        meter.feedCovered(false, at: now)
        let summary = end(at: now + 1)
        XCTAssertTrue(summary.attachmentOpened)
        XCTAssertEqual(summary.attachmentReadMilliseconds, 20_000)
        XCTAssertEqual(summary.activeDwellMilliseconds, 2000)
        XCTAssertEqual(summary.playbackMilliseconds, 2000)
    }

    func testAnAttachmentStillOpenWhenTheExposureEndsIsCountedToThatMoment() {
        meter.shown(1, surface: "for_you", at: 0)
        meter.attachmentOpened(1, at: 1)
        meter.attachmentOpened(1, at: 2)
        XCTAssertEqual(end(at: 6).attachmentReadMilliseconds, 5000)
    }

    func testOnlyAPostTheFeedReportedVisibleIsMeasured() {
        // A card under sixty percent visible is never `shown`, so nothing its
        // player does is recorded.
        meter.hasClip(1, durationMilliseconds: 10_000)
        meter.playing(true, postID: 1, positionMilliseconds: 0, at: 0)
        meter.progress(1, positionMilliseconds: 5000, at: 5)
        XCTAssertNil(meter.hidden(1, at: 6))
        XCTAssertEqual(AttentionMeter.visibleFraction, 0.6)
    }

    func testResetForgetsOpenExposuresAndStartsCountingAgain() {
        meter.shown(1, surface: "for_you", at: 0)
        _ = meter.hidden(1, at: 1)
        meter.shown(2, surface: "for_you", at: 1)
        meter.feedCovered(true, at: 1)
        meter.reset()
        XCTAssertFalse(meter.isExposed(2))
        XCTAssertNil(meter.hidden(2, at: 5))
        meter.shown(3, surface: "for_you", at: 5)
        let summary = end(3, at: 7)
        XCTAssertEqual(summary.sequence, 1)
        XCTAssertEqual(summary.activeDwellMilliseconds, 2000, "the old sheet does not cover the new account")
    }

    func testUnionMergesOverlappingAndTouchingStretches() {
        var ranges: [ClosedRange<Double>] = []
        for added in [5.0...6.0, 1.0...2.0, 2.0...3.0, 8.0...9.0, 2.5...5.5] as [ClosedRange<Double>] {
            ranges = AttentionMeter.union(ranges, with: added)
        }
        XCTAssertEqual(ranges, [1.0...6.0, 8.0...9.0])
    }
}
