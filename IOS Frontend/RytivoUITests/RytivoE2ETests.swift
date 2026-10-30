import XCTest

/// Drives the real app against a real backend.
///
/// Opt-in: the app must be built with `REPBASE_API_URL` pointing at a
/// throwaway server seeded with the accounts below, and the test runner given
/// `TEST_RUNNER_RYTIVO_E2E=1`. Without that, every test skips, so this target
/// can never sign in to a real account by accident.
final class RytivoE2ETests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RYTIVO_E2E"] == "1",
                          "Set TEST_RUNNER_RYTIVO_E2E=1 and a seeded REPBASE_API_URL to run")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private var username: String { ProcessInfo.processInfo.environment["RYTIVO_E2E_USER"] ?? "lifter" }
    private var password: String { ProcessInfo.processInfo.environment["RYTIVO_E2E_PASSWORD"] ?? "" }

    /// Signs in if the app is at the sign-in screen; otherwise does nothing.
    /// The labels are the English ones unless another language is on screen.
    func signInIfNeeded(
        welcome welcomeLabel: String = "Sign In",
        usernamePrompt: String = "Enter your username",
        passwordPrompt: String = "Enter your password",
        submit: String = "Sign in"
    ) {
        // The welcome screen comes first, with its own Sign In button.
        let welcome = app.buttons[welcomeLabel]
        if welcome.waitForExistence(timeout: 8) { welcome.tap() }
        let field = app.textFields[usernamePrompt]
        guard field.waitForExistence(timeout: 8) else { return }
        field.tap()
        field.typeText(username)
        let secure = app.secureTextFields[passwordPrompt]
        secure.tap()
        secure.typeText(password)
        app.buttons[submit].firstMatch.tap()
    }

    /// The same in Spanish, after relaunching in it: the token does not
    /// outlive the process in these unsigned builds.
    func signInInSpanish() {
        signInIfNeeded(welcome: "Iniciar sesión", usernamePrompt: "Ingresa tu nombre de usuario",
                       passwordPrompt: "Ingresa tu contraseña", submit: "Iniciar sesión")
    }

    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func button(labelStartingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    func element(labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func waitUntil(_ timeout: TimeInterval = 10, _ message: String, _ condition: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        shot("failed: \(message)")
        XCTFail("Timed out: \(message)")
    }

    var logButtons: XCUIElementQuery { app.buttons.matching(NSPredicate(format: "label == 'Log set'")) }
    var loggedButtons: XCUIElementQuery { app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Logged'")) }
    var weightFields: XCUIElementQuery { app.textFields.matching(NSPredicate(format: "label BEGINSWITH 'Weight in'")) }
    var repsFields: XCUIElementQuery { app.textFields.matching(NSPredicate(format: "label == 'Reps'")) }

    func openTodayAndStart() {
        signInIfNeeded()
        XCTAssertTrue(app.buttons["Training"].waitForExistence(timeout: 20))
        app.buttons["Training"].tap()
        let today = button(labelStartingWith: "TODAY, Push Day")
        XCTAssertTrue(today.waitForExistence(timeout: 10), "today's workout is offered")
        today.tap()
        let start = button(labelStartingWith: "Start Push Day")
        XCTAssertTrue(start.waitForExistence(timeout: 10), "start button")
        start.tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 20), "session opened")
    }

    /// `preferred`, unless that is today. Today holds the seed's workout and,
    /// from test03 on, a session left open, so its tile opens the session; a
    /// test that needs a plain day takes `fallback` then. Past days of the
    /// week still take new workouts.
    func weekday(_ preferred: String, otherwise fallback: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date()) == preferred ? fallback : preferred
    }

    /// Opens a day of the week and starts a new workout on it: the first, or
    /// another beside what an earlier test left there.
    func createWorkout(onDay prefix: String) {
        let day = button(labelStartingWith: prefix)
        XCTAssertTrue(day.waitForExistence(timeout: 10), prefix)
        day.tap()
        let create = app.buttons["Create a workout"].firstMatch
        let another = app.buttons["Add another workout"]
        waitUntil(10, "\(prefix) offers a workout") { create.exists || another.exists }
        if create.exists {
            create.tap()
        } else {
            for _ in 0..<6 where !another.isHittable { app.swipeUp() }
            another.tap()
        }
    }

    func type(_ text: String, into field: XCUIElement) {
        field.tap()
        field.typeText(text)
    }

    func dismissKeyboard() {
        if app.keyboards.count > 0, app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
    }

    /// Against a backend from before set kinds, rests and supersets: the plan
    /// arrives without them, and nothing new may break the old flow.
    private var legacyBackend: Bool { ProcessInfo.processInfo.environment["RYTIVO_E2E_LEGACY"] == "1" }

    func test02LiftingSession() throws {
        openTodayAndStart()
        shot("01 started")
        XCTAssertTrue(element(labelContaining: "0/13").exists, "13 planned sets")

        // A warm-up offers no working target; it is logged with what is typed.
        if !legacyBackend {
            XCTAssertEqual(weightFields.element(boundBy: 0).placeholderValue, "—", "warm-up has no working target")
        }
        type("40", into: weightFields.element(boundBy: 0))
        type("10", into: repsFields.element(boundBy: 0))
        dismissKeyboard()
        logButtons.element(boundBy: 0).tap()
        waitUntil(15, "warm-up logged") { self.loggedButtons.count == 1 }
        waitUntil(5, "rest started after the set") { self.element(labelContaining: "RESTING").exists }
        XCTAssertTrue(element(labelContaining: "1/13").exists)
        shot("02 warm-up logged, resting")

        // Rest controls.
        app.buttons["Pause rest"].tap()
        waitUntil(5, "paused") { self.element(labelContaining: "PAUSED").exists }
        app.buttons["Add 15 seconds"].tap()
        app.buttons["Resume rest"].tap()
        waitUntil(5, "running again") { self.element(labelContaining: "RESTING").exists }
        app.buttons["Subtract 15 seconds"].tap()
        app.buttons["Skip rest"].tap()
        waitUntil(5, "rest skipped") { self.button(labelStartingWith: "Start rest").exists }
        shot("03 rest skipped")

        // A working set logged straight from its hint: 60 kg × 8.
        logButtons.element(boundBy: 0).tap()
        waitUntil(15, "working set logged from its target") { self.loggedButtons.count == 2 }
        XCTAssertEqual(weightFields.element(boundBy: 1).value as? String, "60")
        XCTAssertEqual(repsFields.element(boundBy: 1).value as? String, "8")
        if app.buttons["Skip rest"].exists { app.buttons["Skip rest"].tap() }

        // Set kind on an unlogged set.
        let thirdSet = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Set kind'")).element(boundBy: 2)
        thirdSet.tap()
        app.buttons["Drop set"].firstMatch.tap()
        waitUntil(5, "set became a drop set") { self.app.buttons["Set kind: Drop set"].exists }
        shot("04 drop set")

        // Units: display only.
        app.buttons["Pounds"].firstMatch.tap()
        waitUntil(5, "pounds shown") { (self.weightFields.element(boundBy: 1).value as? String) == "132.3" }
        app.buttons["Kilograms"].firstMatch.tap()
        waitUntil(5, "kilograms back") { (self.weightFields.element(boundBy: 1).value as? String) == "60" }

        // Add a set to Bench, then delete it again.
        app.buttons["Add set"].firstMatch.tap()
        waitUntil(5, "set added") { self.element(labelContaining: "2/14").exists }
        let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Set kind'")).element(boundBy: 4)
        bench.tap()
        app.buttons["Delete set"].firstMatch.tap()
        waitUntil(10, "set deleted") { self.element(labelContaining: "2/13").exists }

        // Add an exercise from the catalogue.
        app.buttons["Add exercise"].tap()
        let search = app.textFields["Search or create an exercise"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        type("Lateral", into: search)
        let lateral = app.buttons["Add Lateral Raise (Dumbbell)"]
        XCTAssertTrue(lateral.waitForExistence(timeout: 10), "catalogue search finds the exercise")
        lateral.tap()
        waitUntil(15, "added to the session") { self.app.buttons["Remove Lateral Raise (Dumbbell)"].exists }
        shot("05 add exercise sheet")
        app.buttons["Done"].firstMatch.tap()
        waitUntil(10, "fifth exercise card") { self.element(labelContaining: "/5, Exercises").exists }

        // Reorder: Triceps to the top.
        app.buttons["Reorder"].firstMatch.tap()
        let handle = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Reorder' AND label CONTAINS 'Triceps'")).firstMatch
        let firstRow = app.staticTexts["Bench Press"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 10), "drag handle for Triceps")
        handle.press(forDuration: 0.6, thenDragTo: firstRow)
        shot("06 reordered")
        app.buttons["Done"].firstMatch.tap()
        let firstCard = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'exercise 1 of 5'")).firstMatch
        waitUntil(10, "Triceps is first") { firstCard.label.hasPrefix("Triceps Pushdown") }

        // Remove the added exercise again (no sets logged in it).
        app.buttons["Options for Lateral Raise (Dumbbell)"].tap()
        app.buttons["Remove exercise"].firstMatch.tap()
        waitUntil(15, "exercise removed") { self.element(labelContaining: "/4, Exercises").exists }

        // A rest of its own for Bench (planned at 2:00, or the 1:30 default
        // when the backend does not store rests).
        app.buttons[legacyBackend ? "Rest after each set, 1:30" : "Rest after each set, 2:00"].firstMatch.tap()
        if legacyBackend {
            app.buttons["2:00"].firstMatch.tap()
            waitUntil(5, "rest changed") { self.app.buttons["Rest after each set, 2:00"].exists }
            app.buttons["Rest after each set, 2:00"].firstMatch.tap()
        }
        app.buttons["1:30"].firstMatch.tap()
        waitUntil(5, "rest changed") { self.app.buttons["Rest after each set, 1:30"].exists }
        shot("07 before finish")

        // Finish: partial, then the plan question.
        app.buttons["Finish"].firstMatch.tap()
        let partial = app.buttons["Finish and save logged sets"]
        XCTAssertTrue(partial.waitForExistence(timeout: 10), "asked about unfinished sets")
        partial.tap()
        XCTAssertTrue(element(labelContaining: "Keep today’s changes").waitForExistence(timeout: 10), "asked about the plan")
        XCTAssertTrue(element(labelContaining: "Changed the order of exercises").exists)
        shot("08 plan prompt")
        button(labelStartingWith: "Update saved workout").tap()
        XCTAssertTrue(element(labelContaining: "Workout complete").waitForExistence(timeout: 30), "finished")
        shot("09 complete")
    }

    func openSavedWorkouts() {
        signInIfNeeded()
        XCTAssertTrue(app.buttons["Training"].waitForExistence(timeout: 20))
        app.buttons["Training"].tap()
        app.buttons["Workout actions"].firstMatch.tap()
        let saved = button(labelStartingWith: "Saved workouts")
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "quick action")
        saved.tap()
        XCTAssertTrue(element(labelContaining: "Push Day").waitForExistence(timeout: 10), "library lists the workout")
    }

    func test03SavedWorkouts() throws {
        openSavedWorkouts()
        shot("01 library")
        if !legacyBackend {
            XCTAssertTrue(element(labelContaining: "Last done").exists, "last performed is shown")
        }
        XCTAssertTrue(element(labelContaining: "Bench Press").exists, "exercise preview")

        // Duplicate.
        app.buttons["Options for Push Day"].firstMatch.tap()
        app.buttons["Duplicate"].firstMatch.tap()
        XCTAssertTrue(element(labelContaining: "Copied Push Day").waitForExistence(timeout: 15), "copy confirmed")
        XCTAssertTrue(app.buttons["Options for Push Day copy"].waitForExistence(timeout: 10), "copy listed")

        // Delete asks first, naming the workout. Dismissing the question --
        // a popover here, closed by tapping outside it -- keeps the workout.
        app.buttons["Options for Push Day copy"].tap()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Delete Push Day copy"].waitForExistence(timeout: 5), "delete is confirmed")
        shot("01b delete question")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).tap()
        waitUntil(5, "question dismissed") { !self.app.buttons["Delete Push Day copy"].exists }
        XCTAssertTrue(app.buttons["Options for Push Day copy"].exists, "dismissing keeps the workout")
        app.buttons["Options for Push Day copy"].tap()
        app.buttons["Delete"].firstMatch.tap()
        app.buttons["Delete Push Day copy"].firstMatch.tap()
        waitUntil(15, "copy deleted") { !self.app.buttons["Options for Push Day copy"].exists }

        // Edit opens the plan review; drag Cable Fly to the top, save.
        app.buttons["Options for Push Day"].firstMatch.tap()
        app.buttons["Edit"].firstMatch.tap()
        XCTAssertTrue(element(labelContaining: "Review workout").waitForExistence(timeout: 10), "review opens")
        shot("02 review")
        XCTAssertFalse(app.buttons["Move Bench Press up"].exists, "no arrow buttons on the cards")
        app.buttons["Reorder"].firstMatch.tap()
        let handle = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Reorder' AND label CONTAINS 'Cable Fly'")).firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 10), "drag handle for Cable Fly")
        // Onto whichever row is first now: an earlier test may have reordered the plan.
        handle.press(forDuration: 0.6, thenDragTo: app.cells.element(boundBy: 0))
        shot("03 dragged")
        app.buttons["Done"].firstMatch.tap()
        let first = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH '1. '")).firstMatch
        waitUntil(10, "Cable Fly is first") { first.label.hasPrefix("1. Cable Fly") }
        app.buttons["Save workout"].firstMatch.tap()
        XCTAssertTrue(element(labelContaining: "YOUR LIBRARY").waitForExistence(timeout: 20), "saved and closed")

        // Start goes straight into the session.
        button(labelStartingWith: "Start").firstMatch.tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 30), "started from the library")
        shot("04 started from library")
    }

    /// "3. Cable Fly, 3 sets" -> "Cable Fly"
    func cardName(_ label: String) -> String {
        let withoutNumber = label.drop { $0 != " " }.dropFirst()
        return String(withoutNumber.components(separatedBy: ", ").first ?? "")
    }

    func test04ExploreExercises() throws {
        signInIfNeeded()
        XCTAssertTrue(app.buttons["Training"].waitForExistence(timeout: 20))
        app.buttons["Training"].tap()
        let day = weekday("Friday", otherwise: "Thursday")
        createWorkout(onDay: day)
        let name = app.textFields["e.g. Push day"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        type("Core Day", into: name)
        button(labelStartingWith: "Add exercises").tap()
        let search = app.textFields["Search or create an exercise"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        // A name that already exists, in any case, picks that exercise
        // instead of offering to create a duplicate.
        type("pull-up", into: search)
        // The library spells it "Pull Up"; the seed's shared "Pull-Up" is the
        // same exercise, so either way exactly one is offered and no create.
        let pullUp = button(labelStartingWith: "Add Pull")
        XCTAssertTrue(pullUp.waitForExistence(timeout: 10))
        XCTAssertFalse(button(labelStartingWith: "Create “pull-up”").exists, "no duplicate offered for an existing name")
        pullUp.tap()
        // A new one is created from the search.
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        // Not a library exercise: "Cable Crunch" is one now, and is offered
        // rather than created.
        search.typeText("Rytivo Test Hold")
        let createCustom = button(labelStartingWith: "Create “Rytivo Test Hold”")
        XCTAssertTrue(createCustom.waitForExistence(timeout: 10), "offers to create a missing exercise")
        createCustom.tap()
        shot("01 picked")
        // The summary bar steps aside while typing; return dismisses the
        // keyboard and brings it back.
        XCTAssertFalse(button(labelStartingWith: "Review").isHittable, "bar hidden while typing")
        app.typeText("\n")
        let review = button(labelStartingWith: "Review 2 exercises")
        XCTAssertTrue(review.waitForExistence(timeout: 5), "bar back after the keyboard")
        review.tap()
        app.buttons["Save workout"].firstMatch.tap()
        XCTAssertTrue(element(labelContaining: "Core Day").waitForExistence(timeout: 20), "saved")

        // The new exercise is offered straight away the next time.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(button(labelStartingWith: "\(day), Core Day").waitForExistence(timeout: 10), "on the week")
        createWorkout(onDay: weekday("Saturday", otherwise: "Monday"))
        type("Arms", into: app.textFields["e.g. Push day"])
        button(labelStartingWith: "Add exercises").tap()
        XCTAssertTrue(element(labelContaining: "Your exercises").waitForExistence(timeout: 15), "own exercises section")
        XCTAssertTrue(app.buttons["Add Rytivo Test Hold"].waitForExistence(timeout: 10), "created exercise is offered")
        shot("02 explore shows custom")
    }

    func test05Following() throws {
        signInIfNeeded()
        XCTAssertTrue(app.buttons["Social"].waitForExistence(timeout: 20))
        app.buttons["Social"].tap()
        let searchButton = app.buttons["social.search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 10))
        searchButton.tap()
        let field = app.textFields["Name, @handle or #hashtag"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        type("buddy", into: field)
        // Ben follows Lena, and Lena does not follow back yet.
        let followBack = app.buttons["Follow Ben Buddy back"]
        XCTAssertTrue(followBack.waitForExistence(timeout: 15), "search offers Follow back")
        shot("01 search")
        followBack.tap()
        let following = app.buttons["Following Ben Buddy"]
        XCTAssertTrue(following.waitForExistence(timeout: 10), "now following")
        // Leaving is confirmed, never one tap.
        following.tap()
        XCTAssertTrue(app.buttons["Unfollow"].firstMatch.waitForExistence(timeout: 5), "unfollow asks first")
        shot("01b unfollow question")
        // Dismissed without choosing: a popover here, closed by tapping away.
        // Away from the popover and the keyboard: the empty space to its right.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitUntil(5, "question dismissed") { !self.app.buttons["Unfollow"].firstMatch.exists }
        XCTAssertTrue(following.exists, "dismissing keeps the follow")

        // Profile: mutual.
        app.staticTexts["Ben Buddy"].firstMatch.tap()
        XCTAssertTrue(element(labelContaining: "You follow each other").waitForExistence(timeout: 15), "mutual label")
        shot("02 profile mutual")
        let profileFollowing = app.buttons["Following Ben Buddy"].firstMatch
        profileFollowing.tap()
        app.buttons["Unfollow"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Follow Ben Buddy back"].firstMatch.waitForExistence(timeout: 10), "unfollowed")
        XCTAssertTrue(element(labelContaining: "Follows you").exists, "their side stays")
        shot("03 profile after unfollow")
    }

    func test06WorkoutSettings() throws {
        signInIfNeeded()
        XCTAssertTrue(app.buttons["Account"].waitForExistence(timeout: 20))
        app.buttons["Account"].tap()
        let settings = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'settings'")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "settings entry")
        settings.tap()
        let workouts = button(labelStartingWith: "Workouts")
        XCTAssertTrue(workouts.waitForExistence(timeout: 10), "workouts settings row")
        workouts.tap()
        XCTAssertTrue(element(labelContaining: "Default rest").waitForExistence(timeout: 10))
        shot("01 settings")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Default unit'")).firstMatch.tap()
        app.buttons["Pounds (lb)"].firstMatch.tap()
        waitUntil(10, "default unit saved") { self.element(labelContaining: "Pounds (lb)").exists }
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Default unit'")).firstMatch.tap()
        app.buttons["Kilograms (kg)"].firstMatch.tap()
        waitUntil(10, "default unit back") { self.element(labelContaining: "Kilograms (kg)").exists }
    }

    /// A workout can be deleted after it has started. The confirmation is
    /// honoured both ways: Cancel keeps everything, Delete Workout removes the
    /// session and the day offers Start again.
    func test01DiscardStartedWorkout() throws {
        openTodayAndStart()
        // The second row: a working set with a target to log. The first is a
        // warm-up, which has no target and needs numbers typed.
        logButtons.element(boundBy: 1).tap()
        waitUntil(15, "a set is logged") { self.loggedButtons.count == 1 }
        let discard = app.buttons["session-discard"]
        for _ in 0..<12 where !discard.isHittable { app.swipeUp() }
        XCTAssertTrue(discard.isHittable, "discard at the end of the session")
        discard.tap()
        let alert = app.alerts["Delete this workout?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "asks first")
        shot("01 confirm")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Finish"].exists, "cancel keeps the session")
        XCTAssertEqual(loggedButtons.count, 1, "and the logged set")

        // From the Finish prompt as well, like the reference.
        app.buttons["Finish"].tap()
        // The prompt's button, not the one at the end of the session, which
        // has the same label.
        let fromFinish = app.buttons.matching(NSPredicate(format: "label == 'Discard workout' AND identifier != 'session-discard'")).firstMatch
        XCTAssertTrue(fromFinish.waitForExistence(timeout: 5), "finish offers discard")
        fromFinish.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete Workout"].tap()
        XCTAssertTrue(button(labelStartingWith: "Start Push Day").waitForExistence(timeout: 20), "the day can be started again")
        XCTAssertFalse(app.buttons["Finish"].exists, "no session left open")
        shot("02 discarded")
    }

    /// Tennis, logged after the match: time, effort on the chart, calories,
    /// then it is on the day and in recent history, effort and all.
    func test08LogTennis() throws {
        signInIfNeeded()
        XCTAssertTrue(app.buttons["Training"].waitForExistence(timeout: 20))
        app.buttons["Training"].tap()
        // The saved-workouts test leaves a session open. Deleting it is the
        // discard flow again, and frees today.
        let inProgress = button(labelStartingWith: "SESSION IN PROGRESS")
        if inProgress.waitForExistence(timeout: 5) {
            inProgress.tap()
            let discard = app.buttons["session-discard"]
            for _ in 0..<15 where !discard.isHittable { app.swipeUp() }
            discard.tap()
            app.alerts["Delete this workout?"].buttons["Delete Workout"].tap()
            waitUntil(20, "session deleted") { !self.app.buttons["Finish"].exists }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        // Earlier tests put other workouts on today, so today is opened by
        // its card whatever it leads with.
        let today = button(labelStartingWith: "TODAY")
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        today.tap()
        let another = app.buttons["Add another workout"]
        for _ in 0..<6 where !another.isHittable { app.swipeUp() }
        another.tap()
        let tennis = app.buttons["activity-tennis"]
        XCTAssertTrue(tennis.waitForExistence(timeout: 10), "tennis is offered")
        tennis.tap()
        app.buttons["workout-builder-primary"].tap()
        XCTAssertTrue(element(labelContaining: "HOW LONG?").waitForExistence(timeout: 10), "tennis asks for its time")
        XCTAssertTrue(element(labelContaining: "SESSION").exists, "and whether it was a match")
        XCTAssertFalse(element(labelContaining: "DISTANCE").exists, "and not for a distance")
        app.buttons["1 h 00 min"].tap()
        app.buttons["Match"].tap()
        let chart = app.descendants(matching: .any)["effort-chart"].firstMatch
        // All of it above the Save bar: a chart only partly on screen counts
        // as hittable, and its middle can be under the bar or off the screen.
        let saveBar = app.buttons["workout-builder-primary"]
        for _ in 0..<6 where !chart.exists || chart.frame.maxY > saveBar.frame.minY - 8 {
            app.swipeUp(velocity: .slow)
        }
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        // The rating is the chart's value; its label stays "Perceived effort".
        waitUntil(5, "effort chosen on the chart") { (chart.value as? String)?.contains("out of 100") == true }
        shot("01 tennis details")
        let calories = app.textFields["Calories, your estimate"]
        for _ in 0..<4 where !calories.isHittable { app.swipeUp() }
        type("540", into: calories)
        dismissKeyboard()
        app.buttons["workout-builder-primary"].tap()
        XCTAssertTrue(element(labelContaining: "saved to your history").waitForExistence(timeout: 20), "saved")
        XCTAssertTrue(element(labelContaining: "540 kcal").waitForExistence(timeout: 10), "the day shows it")
        XCTAssertTrue(element(labelContaining: "Your estimate").exists, "calories are labelled as an estimate")
        shot("02 tennis on the day")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let recent = element(labelContaining: "Recent activity")
        for _ in 0..<10 where !recent.isHittable { app.swipeUp() }
        XCTAssertTrue(button(labelStartingWith: "Tennis").exists, "in recent history")
        shot("03 recent activity")
    }

    /// The exercise library: an alias finds the exercise, its page explains
    /// it, and the filters narrow a thousand exercises to a few.
    func test09ExerciseLibrary() throws {
        signInIfNeeded()
        XCTAssertTrue(app.buttons["Training"].waitForExistence(timeout: 20))
        app.buttons["Training"].tap()
        // Not Saturday: the explore test leaves an unsaved draft there.
        createWorkout(onDay: weekday("Sunday", otherwise: "Monday"))
        type("Leg Day", into: app.textFields["e.g. Push day"])
        button(labelStartingWith: "Add exercises").tap()
        let search = app.textFields["Search or create an exercise"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        type("rdl", into: search)
        let rdl = button(labelStartingWith: "Add Romanian Deadlift")
        XCTAssertTrue(rdl.waitForExistence(timeout: 10), "an abbreviation finds the exercise")
        XCTAssertFalse(button(labelStartingWith: "Create “rdl”").exists, "no create for a known alias")
        button(labelStartingWith: "How to do Romanian Deadlift").tap()
        XCTAssertTrue(element(labelContaining: "How to do it").waitForExistence(timeout: 5), "steps")
        XCTAssertTrue(element(labelContaining: "Muscles worked").exists, "muscles")
        shot("01 exercise details")
        app.buttons["Add to workout"].tap()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(button(labelStartingWith: "Remove Romanian Deadlift").waitForExistence(timeout: 5), "added from its page")

        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        dismissKeyboard()
        app.typeText("\n")
        app.buttons["Legs"].firstMatch.tap()
        app.buttons["exercise-filters"].tap()
        let equipment = app.buttons["Any"].firstMatch
        XCTAssertTrue(equipment.waitForExistence(timeout: 5), "equipment filter")
        equipment.tap()
        app.buttons["Kettlebell"].firstMatch.tap()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(element(labelContaining: "Filters · 1").waitForExistence(timeout: 5), "one refinement on")
        XCTAssertTrue(element(labelContaining: "Legs · Kettlebell").waitForExistence(timeout: 5), "only kettlebell leg exercises")
        shot("02 filtered")
        let firstKettlebell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ' AND label CONTAINS 'Kettlebell'")).firstMatch
        XCTAssertTrue(firstKettlebell.exists)
        firstKettlebell.tap()
        let review = button(labelStartingWith: "Review 2 exercises")
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        app.buttons["Save workout"].firstMatch.tap()
        XCTAssertTrue(element(labelContaining: "Leg Day").waitForExistence(timeout: 20), "saved with library exercises")
    }

    /// Picks a language in Settings > Language, as somebody would. The labels
    /// to find the way there are passed in, since they are in the language on
    /// screen at the time.
    /// Starts from a tab's root, where the tab bar shows.
    func chooseLanguage(_ nativeName: String, account: String, settings: String, language: String) {
        let accountTab = app.buttons[account]
        XCTAssertTrue(accountTab.waitForExistence(timeout: 20), account)
        accountTab.tap()
        let choice = button(labelStartingWith: nativeName)
        if !choice.waitForExistence(timeout: 2) {
            let settingsButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", settings)).firstMatch
            XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "settings entry")
            settingsButton.tap()
            let row = button(labelStartingWith: language)
            XCTAssertTrue(row.waitForExistence(timeout: 10), "language row")
            for _ in 0..<6 where !row.isHittable { app.swipeUp() }
            row.tap()
        }
        XCTAssertTrue(choice.waitForExistence(timeout: 10), nativeName)
        choice.tap()
    }

    /// The workout screens in another language, chosen in Settings and applied
    /// without a relaunch, then kept across one: activity names, the effort
    /// chart read aloud, and the exercise library found by its Spanish name,
    /// with Spanish steps. Then back to English.
    func test10WorkoutsInAnotherLanguage() throws {
        signInIfNeeded()
        chooseLanguage("Español", account: "Account", settings: "settings", language: "Language")
        waitUntil(10, "switched without a relaunch") { self.app.navigationBars["Idioma"].exists }
        XCTAssertTrue(element(labelContaining: "Tu idioma.").exists, "the whole screen switched, title and all")

        // The rest from a fresh launch, which also shows the choice is kept.
        // Leaving the settings stack by hand is unreliable: a pushed screen
        // hides the tab bar, and a tap where a tab was lands on whatever row
        // is drawn there -- here, another language.
        app.terminate()
        app.launch()
        signInInSpanish()
        let training = app.buttons["Entrenamiento"]
        XCTAssertTrue(training.waitForExistence(timeout: 20), "still Spanish after relaunching")
        training.tap()
        // A day with nothing on it: the seed plans today, and other tests use
        // Friday to Sunday. Weekday 3 is Tuesday.
        let day = Calendar(identifier: .gregorian).component(.weekday, from: Date()) == 3 ? "miércoles" : "martes"
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", day)).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "the week reads in Spanish")
        tile.tap()
        let create = app.buttons["Crear un entrenamiento"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()

        let weightlifting = app.buttons["activity-weightlifting"]
        XCTAssertTrue(weightlifting.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Nuevo entrenamiento"].exists, "a screen opened after the switch is titled in Spanish")
        XCTAssertTrue(weightlifting.label.contains("Levantamiento de pesas"), weightlifting.label)
        XCTAssertTrue(app.buttons["activity-tennis"].label.contains("Tenis"), app.buttons["activity-tennis"].label)
        shot("01 activities in Spanish")

        app.buttons["activity-tennis"].tap()
        let primary = app.buttons["workout-builder-primary"]
        primary.tap()
        let chart = app.descendants(matching: .any)["effort-chart"].firstMatch
        for _ in 0..<6 where !chart.exists || chart.frame.maxY > primary.frame.minY - 8 {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertEqual(chart.label, "Esfuerzo percibido")
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        waitUntil(5, "effort read in Spanish") { (chart.value as? String)?.contains("de 100") == true }
        shot("02 effort chart in Spanish")

        app.buttons["Atrás"].firstMatch.tap()
        XCTAssertTrue(weightlifting.waitForExistence(timeout: 10))
        weightlifting.tap()
        primary.tap()
        let search = app.textFields["exercise-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        type("press de banca", into: search)
        let bench = button(labelStartingWith: "Agregar Press de banca (Barra)")
        XCTAssertTrue(bench.waitForExistence(timeout: 10), "found by its Spanish name, and listed by it")
        button(labelStartingWith: "Cómo hacer Press de banca (Barra)").tap()
        XCTAssertTrue(element(labelContaining: "Cómo hacerlo").waitForExistence(timeout: 5), "the page is in Spanish")
        XCTAssertTrue(element(labelContaining: "Acuéstate boca arriba en un banco plano").exists, "and so are the steps")
        XCTAssertTrue(element(labelContaining: "Bench Press (Barbell)").exists, "the English name is offered too")
        shot("03 exercise page in Spanish")
        app.buttons["Listo"].firstMatch.tap()
        app.buttons["Atrás"].firstMatch.tap()
        app.buttons["Cancelar"].firstMatch.tap()

        app.terminate()
        app.launch()
        signInInSpanish()
        chooseLanguage("English", account: "Cuenta", settings: "Configuración", language: "Idioma")
        waitUntil(10, "back to English") { self.app.navigationBars["Language"].exists }
    }

    /// The seed has Ben follow Lena, then like and comment on her post. The
    /// bell says there is something unread; Activity shows the follow on its
    /// own and the like and comment as one card for the post, counted; that
    /// card opens to each of them.
    func test11Activity() throws {
        signInIfNeeded()
        XCTAssertTrue(app.buttons["Social"].waitForExistence(timeout: 20))
        app.buttons["Social"].tap()
        let bell = app.buttons["Notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 10), "notifications button")
        waitUntil(15, "unread activity is announced") { (bell.value as? String) == "Unread notifications" }
        bell.tap()

        XCTAssertTrue(element(labelContaining: "Ben Buddy started following you").waitForExistence(timeout: 15), "the follow")
        let postCard = element(labelContaining: "Ben Buddy interacted with a post")
        XCTAssertTrue(postCard.exists, "the like and comment, grouped")
        XCTAssertTrue(element(labelContaining: "1 like · 1 comment").exists, "counted, singular in English")
        shot("01 activity")

        postCard.tap()
        XCTAssertTrue(app.navigationBars["Post activity"].waitForExistence(timeout: 10), "the post's activity opened")
        XCTAssertTrue(element(labelContaining: "Ben Buddy liked your post").waitForExistence(timeout: 10), "the like")
        XCTAssertTrue(element(labelContaining: "Ben Buddy commented on your post").exists, "the comment")
        shot("02 post activity")
    }

    /// The calendar's day agenda. Today's planned workout is on it; a task
    /// added from the Calendar tab lands on the selected day, and deleting it
    /// from its actions takes it off again.
    func test12CalendarAgenda() throws {
        signInIfNeeded()
        XCTAssertTrue(app.buttons["Calendar"].waitForExistence(timeout: 20))
        app.buttons["Calendar"].tap()
        XCTAssertTrue(element(labelContaining: "Push Day").waitForExistence(timeout: 20), "today's workout is on the agenda")
        shot("01 agenda")

        let add = app.buttons["Add Task"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "add a task")
        add.tap()
        let title = app.textFields["What needs doing?"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "task editor")
        type("Stretch E2E", into: title)
        dismissKeyboard()
        app.buttons["Add task"].firstMatch.tap()

        let actions = app.buttons["Actions for Stretch E2E"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 15), "the new task is on the agenda")
        shot("02 task added")
        actions.tap()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "delete is offered")
        delete.tap()
        waitUntil(15, "the task is gone") { !actions.exists }
        XCTAssertTrue(element(labelContaining: "Push Day").exists, "the workout stays")
        shot("03 task deleted")
    }
}
