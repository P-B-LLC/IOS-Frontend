import XCTest

/// Touch-driven checks of real views with disconnected, in-memory drafts.
/// Opt-in separately from the signed-in E2E suite; no credentials or server.
final class WorkoutFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RYTIVO_WORKOUT_FLOW"] == "1",
                          "Run the isolated workout-flow capture script with RUN_WORKOUT_FLOW_UI_TESTS=1")
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws { app?.terminate() }

    private func launch(_ scenario: String) {
        app.terminate()
        app.launchEnvironment = ["REPBASE_WORKOUT_PREVIEW": scenario, "REPBASE_APPEARANCE": "light"]
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    private func row(_ number: Int) -> XCUIElement {
        let id = String(format: "workout-builder-exercise-00000000-0000-4000-8000-%012d", number)
        return app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func wait(_ message: String, until condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 8),
                       .completed, message)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func position(of element: XCUIElement) -> Int? {
        guard let value = element.value as? String else { return nil }
        return value.split(separator: " ").dropFirst().first.flatMap { Int($0) }
    }

    func testWholeCardLongPressMovesExerciseAndKeepsReviewTargets() {
        launch("builder-order")
        XCTAssertTrue(row(1).waitForExistence(timeout: 15))
        for _ in 0..<3 where !row(3).isHittable { app.swipeUp() }
        XCTAssertTrue(row(3).isHittable)
        XCTAssertTrue(row(1).isHittable)
        shot("order-before-real-drag")
        // Start on the card's text area, not a system reorder handle.
        let source = row(3).coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        let target = row(1).coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.15))
        source.press(forDuration: 1, thenDragTo: target)
        wait("The dragged card becomes first") { self.position(of: self.row(3)) == 1 }
        XCTAssertEqual(position(of: row(1)), 2)
        shot("order-after-real-drag")

        let review = app.buttons["workout-builder-primary"]
        XCTAssertTrue(review.isHittable)
        review.tap()
        let weight = app.textFields["workout.target-weight.00000000-0000-4000-8000-000000000003"]
        XCTAssertTrue(weight.waitForExistence(timeout: 8))
        for _ in 0..<4 where !weight.isHittable { app.swipeUp() }
        XCTAssertTrue(weight.isHittable)
        XCTAssertEqual(weight.value as? String, "10", "Reordering retains the exercise's target, not its former neighbour's")
        shot("review-keeps-moved-target")
        app.buttons["Back"].firstMatch.tap()
        wait("Back keeps the draft order") { self.position(of: self.row(3)) == 1 }
    }

    func testWholeCardDragCanAutoscrollPastInitiallyVisibleExercises() {
        launch("builder-order")
        XCTAssertTrue(row(1).waitForExistence(timeout: 15))
        let initiallyVisible = (1...12).filter { row($0).exists && row($0).isHittable }
        let lastVisible = initiallyVisible.max() ?? 1
        XCTAssertLessThan(lastVisible, 12, "Fixture must overflow the viewport to test edge scrolling")
        let footer = app.buttons["workout-builder-primary"]
        XCTAssertTrue(footer.isHittable)
        let source = row(1).coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        let edge = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: row(1).frame.midX, dy: footer.frame.minY - 22))
        source.press(forDuration: 1, thenDragTo: edge, withVelocity: .slow, thenHoldForDuration: 6)
        wait("The dragged card moves beyond the original visible rows") {
            (self.position(of: self.row(1)) ?? 0) > lastVisible
        }
        shot("order-after-edge-autoscroll")
    }

    func testVisibleUnitsConvertReviewAndTypedSessionWeight() {
        launch("builder-units")
        let targetID = "workout.target-weight.00000000-0000-4000-8000-000000000001"
        let target = app.textFields[targetID]
        XCTAssertTrue(target.waitForExistence(timeout: 15))
        for _ in 0..<4 where !target.isHittable { app.swipeUp() }
        XCTAssertTrue(target.isHittable)
        XCTAssertEqual(target.value as? String, "60")
        let pounds = app.buttons["workout.weight-unit.imperial"].firstMatch
        let kilos = app.buttons["workout.weight-unit.metric"].firstMatch
        XCTAssertTrue(pounds.isHittable, "Unit choice is visible beside the weight inputs")
        for _ in 0..<3 {
            pounds.tap()
            wait("60 kilograms displays as 132.3 pounds") { (target.value as? String) == "132.3" }
            kilos.tap()
            wait("Switching back preserves 60 kilograms") { (target.value as? String) == "60" }
        }
        XCTAssertTrue(app.buttons["workout.weight-unit-default"].firstMatch.exists)
        shot("review-visible-weight-choice")

        launch("session-units")
        let weights = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.set-weight."))
        XCTAssertTrue(weights.element(boundBy: 2).waitForExistence(timeout: 15))
        let pending = weights.element(boundBy: 2)
        for _ in 0..<3 where !pending.isHittable { app.swipeUp() }
        pending.tap()
        pending.typeText("20")
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
        for _ in 0..<4 where !app.buttons["workout.weight-unit.imperial"].firstMatch.isHittable { app.swipeDown() }
        app.buttons["workout.weight-unit.imperial"].firstMatch.tap()
        wait("Typed unsaved weight converts without being discarded") { (pending.value as? String) == "44.1" }
        app.buttons["workout.weight-unit.metric"].firstMatch.tap()
        wait("Typed unsaved weight round-trips") { (pending.value as? String) == "20" }
        shot("session-visible-weight-choice")
    }
}
