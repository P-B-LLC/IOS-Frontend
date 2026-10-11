import XCTest
@testable import AccountSafety

final class VideoBetaTests: XCTestCase {
    func testAcceptsPortraitAndLandscapeAtLimits() throws {
        try VideoBetaLimits.validate(size: VideoBetaLimits.maximumBytes, seconds: 30, width: 1920, height: 1080, fps: 60)
        try VideoBetaLimits.validate(size: 100, seconds: 1, width: 1080, height: 1920, fps: 30)
    }

    func testRejectsOversizeCorruptDurationAnd4KBeforeUpload() {
        XCTAssertThrowsError(try VideoBetaLimits.validate(size: VideoBetaLimits.maximumBytes + 1, seconds: 1, width: 640, height: 480, fps: 30))
        for duration in [0.0, 30.001, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try VideoBetaLimits.validate(size: 100, seconds: duration, width: 640, height: 480, fps: 30))
        }
        XCTAssertThrowsError(try VideoBetaLimits.validate(size: 100, seconds: 1, width: 3840, height: 2160, fps: 30))
        XCTAssertThrowsError(try VideoBetaLimits.validate(size: 100, seconds: 1, width: 1920, height: 1920, fps: 30))
        XCTAssertThrowsError(try VideoBetaLimits.validate(size: 100, seconds: 1, width: 640, height: 480, fps: 120))
    }
}
