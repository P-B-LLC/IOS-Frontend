import Foundation
import XCTest
@testable import AccountSafety

/// The new Social is off until the server says otherwise, and each part is
/// its own switch.
final class SocialFeedExperienceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        let suite = "SocialFeedExperienceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    private func remember(_ change: (inout SocialFeatures) -> Void, at moment: Date? = nil) {
        var features = SocialFeatures.off
        change(&features)
        SocialFeedExperience.remember(features, in: defaults, now: moment ?? now)
    }

    func testEverythingIsOffBeforeTheServerHasAnswered() {
        XCTAssertFalse(SocialFeedExperience.isEnabled(defaults, now: now))
        XCTAssertFalse(SocialFeedExperience.autoplayPreferred(defaults, now: now))
        XCTAssertFalse(SocialFeedExperience.measures(defaults, now: now))
    }

    func testEachPartIsItsOwnSwitch() {
        remember { $0.newFeed = true }
        XCTAssertTrue(SocialFeedExperience.isEnabled(defaults, now: now))
        XCTAssertFalse(SocialFeedExperience.autoplayPreferred(defaults, now: now))
        XCTAssertFalse(SocialFeedExperience.measures(defaults, now: now))

        remember { $0.measurement = true }
        XCTAssertFalse(SocialFeedExperience.isEnabled(defaults, now: now))
        XCTAssertTrue(SocialFeedExperience.measures(defaults, now: now))
    }

    func testAutoplayNeedsTheServerAndTheReader() {
        remember { $0.autoplay = true }
        XCTAssertTrue(SocialFeedExperience.autoplayPreferred(defaults, now: now))

        defaults.set(false, forKey: SocialFeedExperience.autoplayKey)
        XCTAssertFalse(SocialFeedExperience.autoplayPreferred(defaults, now: now))

        defaults.set(true, forKey: SocialFeedExperience.autoplayKey)
        remember { $0.autoplay = false }
        XCTAssertFalse(SocialFeedExperience.autoplayPreferred(defaults, now: now))
    }

    func testTheLastAnswerStandsForADayAndNoLonger() {
        remember { $0.newFeed = true }

        XCTAssertTrue(SocialFeedExperience.isEnabled(defaults, now: now.addingTimeInterval(23 * 3600)))
        XCTAssertFalse(SocialFeedExperience.isEnabled(defaults, now: now.addingTimeInterval(25 * 3600)))
    }

    func testAnAnswerFromTheFutureIsNotTrusted() {
        remember({ $0.newFeed = true }, at: now.addingTimeInterval(3600))

        XCTAssertFalse(SocialFeedExperience.isEnabled(defaults, now: now))
    }

    func testAPulledBackPartGoesOffWithTheNextAnswer() {
        remember { $0.newFeed = true }
        remember { _ in }

        XCTAssertFalse(SocialFeedExperience.isEnabled(defaults, now: now))
    }

    func testSigningOutForgetsTheAnswer() {
        remember { $0.newFeed = true; $0.measurement = true }

        SocialFeedExperience.forget(in: defaults)

        XCTAssertEqual(SocialFeedExperience.server(defaults, now: now), .off)
    }

    func testATesterCanOverrideTheInterfaceBothWays() {
        defaults.set(true, forKey: SocialFeedExperience.enabledKey)
        XCTAssertTrue(SocialFeedExperience.isEnabled(defaults, now: now))
        // What is drawn, not what is measured or allowed.
        XCTAssertFalse(SocialFeedExperience.measures(defaults, now: now))

        remember { $0.newFeed = true }
        defaults.set(false, forKey: SocialFeedExperience.enabledKey)
        XCTAssertFalse(SocialFeedExperience.isEnabled(defaults, now: now))
    }

    func testAnUnreadableAnswerIsOff() {
        defaults.set(Data("not json".utf8), forKey: SocialFeedExperience.serverKey)
        defaults.set(now, forKey: SocialFeedExperience.serverDateKey)

        XCTAssertEqual(SocialFeedExperience.server(defaults, now: now), .off)
    }
}
