import Foundation
import XCTest
@testable import AccountSafety

/// The credit lines on a take and on a clip set to a sound.
final class SocialTakeCreditTests: XCTestCase {
    func testASourceWithAPostIsAvailable() {
        XCTAssertTrue(PostSourceCredit(postID: 7, authorName: "mia", title: "Rack taken").isAvailable)
    }

    func testASourceTheReaderMayNotSeeIsUnavailableButStillACredit() {
        // Deleted, taken down or made private: the server sends the credit with
        // no post, and the card says only that the original is unavailable.
        let hidden = PostSourceCredit(postID: nil, authorName: nil, title: nil)
        XCTAssertFalse(hidden.isAvailable)
        XCTAssertNotEqual(hidden, PostSourceCredit(postID: 1, authorName: nil, title: nil))
    }

    func testSoundCreditsCompareByEveryField() {
        let sound = PostSoundCredit(id: 3, title: "Plate math", ownerName: "mia")
        XCTAssertEqual(sound, PostSoundCredit(id: 3, title: "Plate math", ownerName: "mia"))
        XCTAssertNotEqual(sound, PostSoundCredit(id: 3, title: "Renamed", ownerName: "mia"))
        XCTAssertNotEqual(sound, PostSoundCredit(id: 4, title: "Plate math", ownerName: "mia"))
        XCTAssertEqual(Set([sound, sound]).count, 1)
    }

    func testAnEmptyTitleOrOwnerIsKeptAsSentNotReplaced() {
        // The server names an untitled sound after its owner; the client
        // shows what it is given rather than inventing a fallback.
        let sound = PostSoundCredit(id: 1, title: "", ownerName: "")
        XCTAssertEqual(sound.title, "")
        XCTAssertEqual(sound.ownerName, "")
    }
}
