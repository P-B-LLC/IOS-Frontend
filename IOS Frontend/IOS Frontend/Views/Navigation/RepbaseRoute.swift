//
//  RepbaseRoute.swift
//  IOS Frontend
//
//  Where a destination sends the app, worked out as data.
//
//  This lived as a switch inside a SwiftUI closure in RepbaseRootView, which
//  meant the one piece of navigation with a history of getting it wrong was
//  also the one piece nothing could check. The rules it encodes are small but
//  they are not obvious -- particularly that arriving somewhere from Home
//  replaces the tab's stack rather than pushing onto it -- and they were got
//  wrong once already, in the arrangement RepbaseNavigation's own note
//  describes: the bar stayed lit on Home while you read the workouts page.
//
//  Nothing here imports SwiftUI, so the routing tests can copy this file and
//  Weekday.swift into a package and check the rules directly.
//

import Foundation

/// The five areas the bottom bar switches between.
nonisolated enum RepbaseTab: String, CaseIterable, Identifiable {
    case home
    /// Workouts and food together. They were a slot each, which is two of five
    /// spent on the two halves of the same day, and left none for the feed.
    case training
    case planner
    case social
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .training: "Training"
        case .planner: "Calendar"
        case .social: "Social"
        case .account: "Account"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .training: "dumbbell"
        case .planner: "calendar"
        case .social: "person.2"
        case .account: "person"
        }
    }

    var iconAsset: String {
        switch self {
        case .home: "RepbaseHome"
        case .training: "RepbaseTraining"
        case .planner: "RepbaseCalendar"
        case .social: "RepbaseSocial"
        case .account: "RepbaseAccount"
        }
    }
}

/// The two halves of a training day, behind one switch.
///
/// `TrainingTabView.Half` is an alias for this. The cases and their titles are
/// here because routing depends on them; the SF Symbol each one draws with
/// stays beside the view, where the icon vocabulary it borrows from lives.
nonisolated enum TrainingHalf: String, CaseIterable, Identifiable {
    case workouts
    case food

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workouts: "Workouts"
        case .food: "Food"
        }
    }
}

/// Somewhere the app can be sent from anywhere in it.
///
/// Home is a summary of four other areas, and every card on it offers to open
/// the one it summarises. Those offers used to be `NavigationLink`s, which
/// pushed the destination onto Home's own stack: you ended up reading the
/// workouts page with the bottom bar still lit on Home, and the way back was
/// a chevron rather than the bar. The bar was describing which tab you
/// started from rather than what you were looking at.
nonisolated enum RepbaseDestination: Hashable {
    case workouts
    /// A specific day's workout, which the workouts tab cannot show on its
    /// own. Selects the tab and pushes the day onto it, so the bar reads
    /// Training and the chevron goes back to the week.
    case workoutDay(Weekday)
    case food
    case planner
    case social
    case account
}

/// What the root view should do to arrive at a destination.
///
/// Separated from the doing so the rules can be read and tested on their own.
/// `RepbaseRootView` applies this and owns the state; it decides nothing.
nonisolated struct RepbaseRoute: Equatable {
    /// The tab to select. Every destination selects one -- that is the whole
    /// point of the type, and what the `NavigationLink`s it replaced failed
    /// to do.
    var tab: RepbaseTab
    /// Which half of the training tab to show, for the destinations that live
    /// on it. nil leaves the tab as the user left it.
    var trainingHalf: TrainingHalf?
    /// Whether the training stack is emptied on the way in.
    ///
    /// Arriving from Home is a fresh trip, not a step deeper into wherever the
    /// tab was left three days ago. Anything that pushes must clear first, or
    /// the back chevron walks through somebody's history instead of returning
    /// to the week.
    var clearsTrainingPath: Bool
    /// A day pushed onto the training stack once it has been cleared.
    var pushesDay: Weekday?

    init(
        tab: RepbaseTab,
        trainingHalf: TrainingHalf? = nil,
        clearsTrainingPath: Bool = false,
        pushesDay: Weekday? = nil
    ) {
        self.tab = tab
        self.trainingHalf = trainingHalf
        self.clearsTrainingPath = clearsTrainingPath
        self.pushesDay = pushesDay
    }

    init(for destination: RepbaseDestination) {
        switch destination {
        case .workouts:
            self.init(tab: .training, trainingHalf: .workouts, clearsTrainingPath: true)
        case .workoutDay(let day):
            self.init(
                tab: .training,
                trainingHalf: .workouts,
                clearsTrainingPath: true,
                pushesDay: day
            )
        case .food:
            self.init(tab: .training, trainingHalf: .food, clearsTrainingPath: true)
        // The three tabs that are only tabs. They keep their own stacks, and
        // nothing about going to them says where in one you should land, so
        // returning to a tab returns to where it was left.
        case .planner:
            self.init(tab: .planner)
        case .social:
            self.init(tab: .social)
        case .account:
            self.init(tab: .account)
        }
    }
}
