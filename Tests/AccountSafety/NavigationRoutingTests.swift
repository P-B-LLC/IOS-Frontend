import XCTest
@testable import AccountSafety

/// Where the app goes when something asks to be taken somewhere.
///
/// The rules are short, and two of them have already been got wrong once. The
/// first is that every destination selects a tab: the home cards used to be
/// `NavigationLink`s that pushed onto Home's own stack, so you read the
/// workouts page with the bottom bar still lit on Home and the way back was a
/// chevron rather than the bar. The second is that arriving replaces the
/// stack rather than adding to it, so the chevron returns to the week instead
/// of walking back through wherever the tab was left three days ago.
///
/// Neither is visible in a screenshot, and neither was checked by anything
/// until this file, because the rules lived inside a SwiftUI closure.
final class NavigationRoutingTests: XCTestCase {
    func testEveryDestinationSelectsATab() {
        let destinations: [RepbaseDestination] = [
            .workouts, .workoutDay(.wednesday), .food, .planner, .social, .account,
        ]
        let tabs = destinations.map { RepbaseRoute(for: $0).tab }
        XCTAssertEqual(tabs, [.training, .training, .training, .planner, .social, .account])
    }

    func testWorkoutsAndFoodShareATabAndDifferByHalf() {
        // The reason there is a Half at all: two areas, one slot in the bar.
        XCTAssertEqual(RepbaseRoute(for: .workouts).trainingHalf, .workouts)
        XCTAssertEqual(RepbaseRoute(for: .food).trainingHalf, .food)
        XCTAssertEqual(RepbaseRoute(for: .workouts).tab, RepbaseRoute(for: .food).tab)
    }

    func testADayIsPushedOntoAClearedStack() {
        let route = RepbaseRoute(for: .workoutDay(.friday))
        XCTAssertEqual(route.pushesDay, .friday)
        XCTAssertTrue(
            route.clearsTrainingPath,
            "pushing without clearing leaves the back chevron in somebody's history"
        )
        XCTAssertEqual(route.trainingHalf, .workouts, "a day is a workout, not a meal")
    }

    func testArrivingAtTheTrainingTabAlwaysClearsFirst() {
        for destination in [RepbaseDestination.workouts, .food, .workoutDay(.monday)] {
            XCTAssertTrue(
                RepbaseRoute(for: destination).clearsTrainingPath,
                "\(destination) arrived without clearing"
            )
        }
    }

    func testTheOtherTabsAreLeftWhereTheyWere() {
        // Each tab keeps its own stack, and nothing about "go to the planner"
        // says where in the planner. Touching the training state from here
        // would also reach across into a tab the user did not ask about.
        for destination in [RepbaseDestination.planner, .social, .account] {
            let route = RepbaseRoute(for: destination)
            XCTAssertNil(route.trainingHalf, "\(destination) changed the training half")
            XCTAssertNil(route.pushesDay, "\(destination) pushed a day")
            XCTAssertFalse(
                route.clearsTrainingPath,
                "\(destination) cleared a stack belonging to another tab"
            )
        }
    }

    func testTheDayCarriedIsTheDayAskedFor() {
        for day in Weekday.allCases {
            XCTAssertEqual(RepbaseRoute(for: .workoutDay(day)).pushesDay, day)
        }
    }

    func testATabIsIdentifiedByItsNameSoTheLaunchFlagCanNameOne() {
        // REPBASE_TAB is read with RepbaseTab(rawValue:), which is how a
        // screen several taps in gets looked at without a tap.
        XCTAssertEqual(RepbaseTab(rawValue: "social"), .social)
        XCTAssertEqual(RepbaseTab(rawValue: "training"), .training)
        XCTAssertNil(RepbaseTab(rawValue: "Social"), "the flag is matched exactly")
        XCTAssertEqual(Set(RepbaseTab.allCases.map(\.rawValue)).count, RepbaseTab.allCases.count)
    }
}
