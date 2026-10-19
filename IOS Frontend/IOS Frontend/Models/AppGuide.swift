//
//  AppGuide.swift
//  IOS Frontend
//
//  The welcome guide as data: what it says, who sees which part, which tab
//  each step stands on, and when it opens by itself.
//
//  Nothing here imports SwiftUI, so the account-safety package can copy this
//  file beside RepbaseRoute.swift and test the rules directly. The overlay
//  that draws it is Views/Guide/AppGuideOverlay.swift.
//

import Foundation

/// What this account can open beyond what everybody can. Leaving a step out
/// is not a lock -- the server checks again -- but a tour of rooms somebody
/// cannot enter is a worse tour.
nonisolated struct AppGuideAccess: Equatable, Sendable {
    var moderate = false
}

nonisolated struct AppGuideStep: Identifiable, Equatable, Sendable {
    enum Requirement: Equatable, Sendable { case moderate }

    let id: String
    let title: String
    let body: String
    /// The tab shown behind the step, so what is lit is what is described.
    let tab: RepbaseTab
    /// Lights that tab's button in the bottom bar. A step that lights nothing
    /// is a card on its own in the middle of the screen.
    let highlightsTab: Bool
    let requires: Requirement?

    init(
        id: String, title: String, body: String, tab: RepbaseTab,
        highlightsTab: Bool = true, requires: Requirement? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tab = tab
        self.highlightsTab = highlightsTab
        self.requires = requires
    }
}

nonisolated enum AppGuide {
    static let steps: [AppGuideStep] = [
        AppGuideStep(
            id: "welcome",
            title: "Welcome to Rytivo",
            body: "A quick look round: where things are, and what each part is for. It takes about a minute, and you can leave whenever you like.",
            tab: .home,
            highlightsTab: false
        ),
        AppGuideStep(
            id: "home",
            title: "Home is your day",
            body: "Your weekly goal, what is next today, and your food and steps at a glance. Tap a day on the strip to see that day instead.",
            tab: .home
        ),
        AppGuideStep(
            id: "training",
            title: "Training: workouts and food",
            body: "Plan each day's workout, then start it and log every set. Switch to Food to log meals, and use + for quick actions like saved workouts.",
            tab: .training
        ),
        AppGuideStep(
            id: "calendar",
            title: "Calendar plans your weeks",
            body: "Add tasks and workouts to any day. A task can have steps, repeat on the days you choose, and remind you when it is due.",
            tab: .planner
        ),
        AppGuideStep(
            id: "social",
            title: "Social: share and follow",
            body: "Post a session, a meal or a photo. For You suggests posts you may like, Following shows the people you chose, and Discover finds new people.",
            tab: .social
        ),
        AppGuideStep(
            id: "account",
            title: "Account is you",
            body: "Your profile, posts and progress. The menu button beside your name opens Settings: privacy, notifications, Apple Health and Help.",
            tab: .account
        ),
        AppGuideStep(
            id: "moderation",
            title: "Moderation dashboard",
            body: "You can review flagged posts and approve or reject them. The dashboard is at the top of Settings and asks you to sign in separately.",
            tab: .account,
            requires: .moderate
        ),
        AppGuideStep(
            id: "done",
            title: "You are ready",
            body: "Start with whatever you came for. Short tips appear the first time you reach some screens, and Settings → Help replays this tour.",
            tab: .home,
            highlightsTab: false
        ),
    ]

    /// The tour this account gets: everything, less what it cannot open.
    static func steps(for access: AppGuideAccess) -> [AppGuideStep] {
        steps.filter { step in
            switch step.requires {
            case nil: true
            case .moderate: access.moderate
            }
        }
    }

    /// Whether the guide should open by itself, without being asked.
    ///
    /// `server` is what `/me/guide/ios/` said, or nil when it could not be
    /// asked -- an older server without the endpoint, or no connection. Not
    /// knowing is a no, except for an account made a moment ago in this app:
    /// that one is new whatever the server can say. `seenHere` is this
    /// phone's own note that the tour was finished or skipped, which also
    /// covers the server never hearing so.
    static func opensByItself(server: Bool?, seenHere: Bool, justRegistered: Bool) -> Bool {
        guard !seenHere else { return false }
        if let server { return !server }
        return justRegistered
    }

    /// Kept per account and per server, as the drafts are: two people
    /// sharing a phone each get their own tour and their own tips.
    static func seenKey(accountID: Int, origin: String) -> String {
        "rytivo.guide.ios.\(origin).\(accountID)"
    }

    static func tipsKey(accountID: Int, origin: String) -> String {
        "rytivo.tips.\(origin).\(accountID)"
    }
}

/// Where somebody is in the tour. A value, so moving through it is tested
/// without a screen.
nonisolated struct AppGuideProgress: Equatable, Sendable {
    let steps: [AppGuideStep]
    private(set) var index = 0

    init(steps: [AppGuideStep]) {
        precondition(!steps.isEmpty, "A tour needs at least one step")
        self.steps = steps
    }

    var step: AppGuideStep { steps[index] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == steps.count - 1 }
    /// "Step 2 of 7", as the sign-up questions count theirs.
    var position: String { "Step \(index + 1) of \(steps.count)" }
    var fraction: Double { Double(index + 1) / Double(steps.count) }

    mutating func next() {
        index = min(index + 1, steps.count - 1)
    }

    mutating func back() {
        index = max(index - 1, 0)
    }
}

/// The short notes shown once, where the feature they explain is.
nonisolated enum AppGuideTip: String, CaseIterable, Sendable {
    case home
    case training
    case calendar
    case social

    var text: String {
        switch self {
        case .home:
            "Home leads with what you chose when you set up Rytivo. Change it any time in Settings → Your Rytivo."
        case .training:
            "Tap a day in your week to plan it, then start the session there and log each set as you go."
        case .calendar:
            "Tap a day to see it, then add to it. Open a task to give it steps, or to make it repeat."
        case .social:
            "For You learns from what you like, save and pass on. A post's ⋯ menu shows more or fewer like it, and the sliders tune the whole feed."
        }
    }
}
