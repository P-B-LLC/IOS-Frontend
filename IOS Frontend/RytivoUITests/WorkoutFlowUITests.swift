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
        XCTAssertEqual(app.state, .notRunning, "A scenario starts from a terminated app, not a previous simctl preview")
        app.launchEnvironment = ["REPBASE_WORKOUT_PREVIEW": scenario, "REPBASE_APPEARANCE": "light"]
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if scenario.hasPrefix("builder-") {
            let title = scenario == "builder-units" ? "Review workout" : "Add exercises"
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15),
                          "The isolated scenario must open before checking its controls")
        }
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

    private func hierarchy(_ name: String) {
        // This class only launches isolated, accountless fixtures.
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func position(of element: XCUIElement) -> Int? {
        guard element.exists else { return nil }
        guard let value = element.value as? String else { return nil }
        return value.split(separator: " ").dropFirst().first.flatMap { Int($0) }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func reveal(_ element: XCUIElement, scrollingUp: Bool, maximumSwipes: Int = 8) {
        for _ in 0..<maximumSwipes {
            if element.exists && element.isHittable { return }
            if scrollingUp { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "The requested control must be visible before interacting")
    }

    private func assertNoUnitDefaultAction() {
        XCTAssertFalse(app.buttons["workout.weight-unit-default"].exists,
                       "An exercise unit choice must not offer to change the account default")
    }

    private func assertBuilderHasNoUnitSwitch() {
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout.exercise-unit.")).firstMatch.exists)
        XCTAssertFalse(app.buttons["workout.weight-unit.metric"].exists)
        XCTAssertFalse(app.buttons["workout.weight-unit.imperial"].exists)
        assertNoUnitDefaultAction()
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
        // Release after the native insertion gap settles, not at the exact
        // timestamp the pointer first reaches its destination.
        source.press(forDuration: 1, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
        shot("order-immediately-after-short-drag")
        hierarchy("order-after-short-drag-hierarchy")
        wait("The dragged card becomes first") { self.position(of: self.row(3)) == 1 }
        XCTAssertEqual(position(of: row(1)), 2)
        shot("order-after-real-drag")

        let review = app.buttons["workout-builder-primary"]
        XCTAssertTrue(review.isHittable)
        review.tap()
        let weight = app.textFields["workout.plan-set.00000000-0000-4000-8000-000000000003.1.weight"]
        reveal(weight, scrollingUp: true)
        XCTAssertEqual(weight.value as? String, "10", "Reordering retains the exercise's target, not its former neighbour's")
        assertBuilderHasNoUnitSwitch()
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
        let list = app.descendants(matching: .any).matching(identifier: "workout-builder-list").firstMatch
        XCTAssertTrue(list.exists)
        let count = app.staticTexts["workout-builder-draft-count"]
        XCTAssertTrue(count.exists)
        let source = row(1).coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        // Keep the hold inside the visible List, above the entire footer.
        // Some OS versions report a scroll view frame beneath safeAreaInset;
        // its count label is 12pt inside that footer, so clamp against it too.
        let edgeY = min(list.frame.maxY, count.frame.minY - 12) - 8
        let edge = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: row(1).frame.midX, dy: edgeY))
        // Six seconds scrolled all the way into the catalog, where no plan
        // row can be dropped. Exercise edge scrolling inside the plan instead.
        source.press(forDuration: 1, thenDragTo: edge, withVelocity: .slow, thenHoldForDuration: 1)
        shot("order-after-edge-drag-before-reveal")
        hierarchy("order-after-edge-drag-hierarchy")
        // Native List virtualizes rows after edge scrolling. Find the moved
        // card again before reading its value; scrolling does not reorder it.
        for _ in 0..<6 where !row(1).exists { app.swipeDown() }
        for _ in 0..<6 where !row(1).exists { app.swipeUp() }
        XCTAssertTrue(row(1).exists, "The moved exercise must still be in the draft")
        wait("The dragged card moves beyond the original visible rows") {
            (self.position(of: self.row(1)) ?? 0) > lastVisible
        }
        shot("order-after-edge-autoscroll")
    }

    func testBuilderUsesAccountUnitWithoutAnExerciseUnitSwitch() {
        launch("builder-units")
        let target = app.textFields["workout.plan-set.00000000-0000-4000-8000-000000000001.1.weight"]
        reveal(target, scrollingUp: true)
        XCTAssertEqual(target.value as? String, "60")
        assertBuilderHasNoUnitSwitch()
        shot("review-without-unit-switch")
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Add exercises"].waitForExistence(timeout: 8))
        assertBuilderHasNoUnitSwitch()
    }

    func testActiveExercisesKeepIndependentUnitsAndTypedWeights() {
        launch("session-units")
        let benchPounds = app.buttons["workout.exercise-unit.101.imperial"]
        let benchKilos = app.buttons["workout.exercise-unit.101.metric"]
        let inclinePounds = app.buttons["workout.exercise-unit.102.imperial"]
        let inclineKilos = app.buttons["workout.exercise-unit.102.metric"]
        let benchLogged = app.textFields["workout.set-weight.101.1"]
        let benchPending = app.textFields["workout.set-weight.101.3"]
        let inclinePending = app.textFields["workout.set-weight.102.1"]
        XCTAssertTrue(benchKilos.waitForExistence(timeout: 15))
        XCTAssertTrue(benchKilos.isSelected)
        XCTAssertTrue(inclineKilos.isSelected)
        XCTAssertEqual(benchLogged.value as? String, "60")
        assertNoUnitDefaultAction()

        reveal(benchPending, scrollingUp: true)
        benchPending.tap()
        benchPending.typeText("20")
        app.buttons["Done"].firstMatch.tap()
        reveal(benchPounds, scrollingUp: false)
        benchPounds.tap()
        wait("Only Bench converts its typed and logged weights to pounds") {
            (benchPending.value as? String) == "44.1" && (benchLogged.value as? String) == "132.3"
        }
        XCTAssertTrue(benchPounds.isSelected)
        XCTAssertTrue(inclineKilos.isSelected, "Changing Bench must not change Incline's unit")
        assertNoUnitDefaultAction()
        shot("bench-pounds-other-exercises-still-kilograms")

        reveal(inclinePending, scrollingUp: true)
        inclinePending.tap()
        inclinePending.typeText("22")
        app.buttons["Done"].firstMatch.tap()
        reveal(inclinePounds, scrollingUp: false)
        inclinePounds.tap()
        wait("Incline independently converts its typed weight") { (inclinePending.value as? String) == "48.5" }
        XCTAssertTrue(inclinePounds.isSelected)
        XCTAssertEqual(benchPending.value as? String, "44.1", "Changing Incline must not discard or reconvert Bench input")
        XCTAssertTrue(benchPounds.isSelected)

        reveal(benchKilos, scrollingUp: false)
        benchKilos.tap()
        wait("Bench round-trips without changing another exercise") {
            (benchPending.value as? String) == "20" && (benchLogged.value as? String) == "60"
        }
        XCTAssertTrue(benchKilos.isSelected)
        XCTAssertTrue(inclinePounds.isSelected)
        XCTAssertEqual(inclinePending.value as? String, "48.5")
        assertNoUnitDefaultAction()
        shot("bench-kilograms-incline-still-pounds")
        reveal(inclinePounds, scrollingUp: true)
        XCTAssertTrue(inclinePounds.isSelected)
        XCTAssertEqual(inclinePending.value as? String, "48.5")
        shot("incline-keeps-its-own-pounds-choice")
    }

    /// Actual editing of the real table in an in-memory draft. A separate
    /// real-API save/reopen test is required to establish server persistence.
    func testPerSetPlanKeepsDistinctTargetsAndSupportsExplicitCopy() {
        launch("builder-units")
        let prefix = "workout.plan-set.00000000-0000-4000-8000-000000000001"
        func weight(_ number: Int) -> XCUIElement { app.textFields["\(prefix).\(number).weight"] }
        func reps(_ number: Int) -> XCUIElement { app.textFields["\(prefix).\(number).reps"] }
        func replace(_ field: XCUIElement, with text: String) {
            reveal(field, scrollingUp: true)
            field.tap()
            let current = field.value as? String ?? ""
            if current != field.placeholderValue {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            field.typeText(text)
            app.buttons["Done"].firstMatch.tap()
        }
        replace(reps(1), with: "6")
        replace(weight(1), with: "40")
        replace(reps(2), with: "8")
        replace(weight(2), with: "60")
        XCTAssertEqual(reps(1).value as? String, "6")
        XCTAssertEqual(weight(1).value as? String, "40")
        XCTAssertEqual(reps(2).value as? String, "8")
        XCTAssertEqual(weight(2).value as? String, "60")
        assertBuilderHasNoUnitSwitch()
        shot("planned-sets-have-distinct-targets")

        let add = app.buttons["\(prefix).add"]
        reveal(add, scrollingUp: true)
        add.tap()
        reveal(weight(4), scrollingUp: true)
        XCTAssertTrue(reps(4).exists, "Add set creates another independent target row")
        let remove = app.buttons["\(prefix).3.remove"]
        reveal(remove, scrollingUp: false)
        remove.tap()
        XCTAssertFalse(weight(4).exists)
        XCTAssertEqual(weight(1).value as? String, "40")
        XCTAssertEqual(weight(2).value as? String, "60", "Removing another set must preserve existing targets")

        let copy = app.buttons["\(prefix).copy-first"]
        reveal(copy, scrollingUp: true)
        copy.tap()
        reveal(weight(1), scrollingUp: false)
        for index in 1...3 {
            XCTAssertEqual(reps(index).value as? String, "6")
            XCTAssertEqual(weight(index).value as? String, "40")
        }
        shot("planned-targets-copy-only-when-requested")
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Add exercises"].waitForExistence(timeout: 8))
        app.buttons["workout-builder-primary"].tap()
        reveal(weight(2), scrollingUp: true)
        XCTAssertEqual(reps(2).value as? String, "6")
        XCTAssertEqual(weight(2).value as? String, "40", "Returning to review retains the edited draft")
    }
}
