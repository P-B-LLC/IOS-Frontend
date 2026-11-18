import Foundation
import XCTest

/// Wiring checks only. Native preview captures are still required to review
/// actual crop, photo visibility and text readability in both appearances.
final class PhotoBackgroundPresentationTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        return try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(path), encoding: .utf8)
    }

    func testHomeFocusUsesTheBrighterTreatmentForAllThreePhotos() throws {
        let home = try source("IOS Frontend/IOS Frontend/Views/Home/GuidedHomeView.swift")
        XCTAssertEqual(home.components(separatedBy: "emphasizesPhoto: true").count - 1, 3)
        XCTAssertTrue(home.contains("RytivoPhotoBackground(asset: \"SunriseFoodPhoto\", emphasizesPhoto: true)"))
        XCTAssertTrue(home.contains("RytivoPhotoBackground(asset: \"TrainingOutdoors\", emphasizesPhoto: true)"))
        XCTAssertTrue(home.contains("TrainingPhoto.asset(for: workout?.activity), emphasizesPhoto: true"))
    }

    func testReadabilityFallbackAndOtherCardStylesRemainAvailable() throws {
        let backdrop = try source("IOS Frontend/IOS Frontend/Views/Shared/RytivoSunriseDesign.swift")
        XCTAssertTrue(backdrop.contains("var emphasizesPhoto = false"))
        XCTAssertTrue(backdrop.contains("guard emphasizesPhoto, asset != nil else"))
        XCTAssertTrue(backdrop.contains("contrast == .increased || typeSize.isAccessibilitySize"))
        XCTAssertTrue(backdrop.contains(".black.opacity(stronger ? 0.60 : 0.24), location: 0.32"))
        XCTAssertTrue(backdrop.contains(".interpolation(.high).scaledToFill()"))
        XCTAssertTrue(backdrop.contains(".allowsHitTesting(false)"))
        for file in ["Views/Workouts/TrainingDashboardContent.swift", "Views/Profile/SocialProfileView.swift"] {
            XCTAssertFalse(try source("IOS Frontend/IOS Frontend/" + file).contains("emphasizesPhoto: true"))
        }
    }
}
