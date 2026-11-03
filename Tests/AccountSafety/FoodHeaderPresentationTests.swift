import Foundation
import XCTest

/// Source-wiring guards, not rendered UI or interaction tests. The existing
/// native simulator preview job supplies light/dark and layout evidence.
final class FoodHeaderPresentationTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        return try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(path), encoding: .utf8)
    }

    func testGoalsKeepsItsExistingEditorAndMonthAction() throws {
        let view = try source("IOS Frontend/IOS Frontend/Views/Food/FoodTrackingView.swift")
        let start = try XCTUnwrap(view.range(of: "private var goalsButton: some View {"))
        let end = try XCTUnwrap(view.range(of: "private func weekSelector", range: start.upperBound..<view.endIndex))
        let button = String(view[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(button.contains("isEditingGoals = true"))
        XCTAssertTrue(view.contains(".fullScreenCover(isPresented: $isEditingGoals) {\n            NutritionGoalsView()"))
        XCTAssertTrue(view.contains("Button { isShowingMonth = true } label:"))
        XCTAssertTrue(button.contains(".accessibilityIdentifier(\"food.goals\")"))
        XCTAssertTrue(button.contains(".accessibilityHint(\"Change calorie and macronutrient targets\")"))
    }

    func testVisibleGoalsAffordanceAdaptsWithoutFixedTextOrHeight() throws {
        let view = try source("IOS Frontend/IOS Frontend/Views/Food/FoodTrackingView.swift")
        XCTAssertTrue(view.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(view.contains("foodHeaderDateAndGoals(timeOfDay: timeOfDay)"))
        XCTAssertTrue(view.contains(".frame(minWidth: 104, minHeight: 44)"))
        XCTAssertTrue(view.contains(".background(RepbaseTactileDesign.surface, in: Capsule())"))
        XCTAssertTrue(view.contains("RepbaseTactileDesign.accentText.opacity(contrast == .increased ? 1 : 0.55)"))
        XCTAssertTrue(view.contains(".contentShape(Capsule())"))
        XCTAssertTrue(view.contains(".buttonStyle(RepbaseTactilePressStyle())"))
        XCTAssertTrue(view.contains(".locale(.app)"))
    }

    func testExactTargetAssetIsLocalVectorTemplateInItsDesignSlot() throws {
        let view = try source("IOS Frontend/IOS Frontend/Views/Food/FoodTrackingView.swift")
        XCTAssertTrue(view.contains("Image(\"FoodGoalsTarget\")"))
        XCTAssertTrue(view.contains(".frame(width: 16, height: 16)"))
        let asset = "IOS Frontend/IOS Frontend/Assets.xcassets/FoodGoalsTarget.imageset/"
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try source(asset + "Contents.json").utf8)) as? [String: Any])
        let properties = try XCTUnwrap(metadata["properties"] as? [String: Any])
        XCTAssertEqual(properties["template-rendering-intent"] as? String, "template")
        XCTAssertEqual(properties["preserves-vector-representation"] as? Bool, true)
        let svg = try source(asset + "target.svg")
        XCTAssertTrue(svg.contains("<svg"))
        XCTAssertTrue(svg.contains("width=\"14.9333\" height=\"14.9333\""))
        XCTAssertFalse(svg.contains("<image"))
        XCTAssertFalse(svg.contains("https://www.figma.com/api/"))
    }
}
