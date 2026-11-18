import Foundation
import XCTest

/// These checks guard the shared branding wiring, not native rendering.
/// Simulator review is still required for the actual light/dark appearance,
/// narrow headers, Dynamic Type and the installed home-screen icon.
final class RytivoBrandPresentationTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        return try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(path), encoding: .utf8)
    }

    func testWordmarkKeepsApprovedCaseTypefaceAndTracking() throws {
        let view = try source("IOS Frontend/IOS Frontend/Views/Shared/EditorialFormComponents.swift")
        XCTAssertTrue(view.contains("Text(verbatim: \"rytivo\")"))
        XCTAssertTrue(view.contains(".font(.community(size: fontSize, weight: .semibold))"))
        XCTAssertTrue(view.contains(".tracking(-fontSize * 0.01)"))
        XCTAssertTrue(view.contains(".foregroundStyle(Color(\"RytivoBrandInk\"))"))
        XCTAssertFalse(view.contains("Text(\"Rytivo\")"))

        let typography = try source("IOS Frontend/IOS Frontend/Views/Shared/CommunityTypography.swift")
        XCTAssertTrue(typography.contains("semiboldPostScriptName = \"NunitoSans-SemiBold\""))
        XCTAssertTrue(typography.contains("weight == .medium || weight == .semibold"))
    }

    func testSharedLockupScalesTheApprovedGeometryTogether() throws {
        let view = try source("IOS Frontend/IOS Frontend/Views/Shared/EditorialFormComponents.swift")
        XCTAssertTrue(view.contains("HStack(spacing: size * 8 / 112)"))
        XCTAssertTrue(view.contains("RytivoWordmark(fontSize: size * 66 / 112)"))
        XCTAssertTrue(view.contains(".frame(width: size, height: size)"))
        XCTAssertTrue(view.contains("Image(\"RytivoLogoMark\")"))
        XCTAssertFalse(view.contains("var foregroundColor: Color?"))
    }

    func testBrandHasOneAccessibleNameAndStableLatinOrder() throws {
        let view = try source("IOS Frontend/IOS Frontend/Views/Shared/EditorialFormComponents.swift")
        XCTAssertTrue(view.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertTrue(view.contains(".accessibilityLabel(Text(verbatim: \"Rytivo\"))"))
        XCTAssertTrue(view.contains(".environment(\\.layoutDirection, .leftToRight)"))
        XCTAssertTrue(view.contains(".typeSizeCeiling(.large)"))
    }

    func testAuthenticationAndCalendarUseTheSharedIdentity() throws {
        let authentication = try source("IOS Frontend/IOS Frontend/Views/Authentication/AuthenticationView.swift")
        XCTAssertTrue(authentication.contains("RytivoBrandLockup(size: 38)"))
        XCTAssertTrue(authentication.contains("RytivoWordmark(fontSize: 29)"))
        XCTAssertFalse(authentication.contains("Text(\"Rytivo\")"))

        let planner = try source("IOS Frontend/IOS Frontend/Views/Planner/PlannerView.swift")
        XCTAssertTrue(planner.contains("RytivoBrandLockup(size: 24)"))
        XCTAssertFalse(planner.contains("Text(\"Rytivo\")"))
    }

    func testExistingBrandPlacementsKeepTheSharedLocalAsset() throws {
        let app = try source("IOS Frontend/IOS Frontend/IOS_FrontendApp.swift")
        let profile = try source("IOS Frontend/IOS Frontend/Views/Profile/SocialProfileView.swift")
        let training = try source("IOS Frontend/IOS Frontend/Views/Navigation/TrainingTabView.swift")
        let food = try source("IOS Frontend/IOS Frontend/Views/Food/FoodTrackingView.swift")
        XCTAssertTrue(app.contains("Image(\"RytivoLogoMark\")"))
        XCTAssertTrue(profile.contains("Image(\"RytivoLogoMark\")"))
        XCTAssertTrue(training.contains("RytivoBrandLockup(size: 24)"))
        XCTAssertTrue(food.contains("RytivoBrandLockup(size: 24)"))
    }
}
