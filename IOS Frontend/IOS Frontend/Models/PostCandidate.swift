//
//  PostCandidate.swift
//  IOS Frontend
//
//  What the composer can offer to post.
//
//  A candidate is a reference and a label, never contents. The server reads the
//  workout, meal or entry itself and builds the snapshot from it, so nothing
//  gathered here decides what a post ends up claiming was done.
//

import Foundation

/// A finished session, reduced to what the composer needs to list one.
nonisolated struct PostableSession: Identifiable, Hashable, Sendable {
    let sessionID: Int
    /// Nullable only when the session has no surviving template. Never infer
    /// this identity from the display name for completion or deletion.
    let workoutServerID: Int?
    let workoutName: String
    /// When it happened: the end of the session, or its start when it never
    /// recorded an end.
    let performedAt: Date
    let durationSeconds: Double?
    let routeDistanceKilometers: Double?
    /// The sport, which decides what counts as having trained. Nil when the
    /// workout behind the session has since been deleted.
    let workoutType: WorkoutType?
    /// How many sets the session recorded, counted by the server.
    let loggedSetCount: Int
    /// Effort, entered values and details. Empty from a server that predates
    /// them, and for a lifting session nobody rated.
    var activitySummary: SessionActivitySummary

    /// The activity, from the server when it says, else the type's own.
    var activity: WorkoutActivity? {
        activitySummary.activity ?? workoutType.map(WorkoutActivity.legacyDefault(for:))
    }

    init(
        sessionID: Int,
        workoutServerID: Int? = nil,
        workoutName: String,
        performedAt: Date,
        durationSeconds: Double?,
        routeDistanceKilometers: Double?,
        workoutType: WorkoutType?,
        loggedSetCount: Int,
        activitySummary: SessionActivitySummary = SessionActivitySummary()
    ) {
        self.sessionID = sessionID
        self.workoutServerID = workoutServerID
        self.workoutName = workoutName
        self.performedAt = performedAt
        self.durationSeconds = durationSeconds
        self.routeDistanceKilometers = routeDistanceKilometers
        self.workoutType = workoutType
        self.loggedSetCount = loggedSetCount
        self.activitySummary = activitySummary
    }

    var id: Int { sessionID }

    /// Whether the session recorded any training at all.
    ///
    /// A session is finished by tapping Finish, not by logging anything, so a
    /// completed session can hold nothing, and a day that recorded nothing
    /// should not claim to have been trained.
    ///
    /// What counts as nothing depends on the sport. Lifting has sets. A run,
    /// ride or swim has none, and used to be judged on distance alone — which
    /// meant a treadmill run, a run with location refused, or any run on a
    /// simulator recorded "nothing" and never got its completed badge. Time is
    /// the evidence there: a run that took twenty minutes happened, whether or
    /// not GPS was watching.
    ///
    /// Every activity that is not sets-based is judged the same way: a tennis
    /// match or a yoga class logged with its length happened.
    var recordedSomething: Bool {
        SessionTraining.recordedSomething(
            activity: activity,
            loggedSetCount: loggedSetCount,
            durationSeconds: durationSeconds,
            distanceKilometers: activitySummary.distanceKilometers ?? routeDistanceKilometers
        )
    }
}

/// The three places a post can come from, in the order the picker offers them.
///
/// Deliberately separate from `PostKind`: that is the contract's word for what
/// a post is, while this is the app's word for where the user goes to make one,
/// and the two need not stay in step if the contract learns a fourth kind.
nonisolated enum PostSource: String, CaseIterable, Identifiable, Sendable {
    case workout
    case meal
    case planner

    var id: String { rawValue }

    /// The tab the thing being posted lives on, so the choice reads as a place
    /// the user has already been rather than a new piece of vocabulary.
    var title: String {
        switch self {
        case .workout: String(localized: "Workout", bundle: .app, locale: .app)
        case .meal: String(localized: "Food", bundle: .app, locale: .app)
        case .planner: String(localized: "Calendar", bundle: .app, locale: .app)
        }
    }

    var symbol: String {
        switch self {
        case .workout: ActivityIconKind.lifting.systemName
        case .meal: "fork.knife"
        case .planner: "calendar"
        }
    }

    /// Says what would put something here, rather than only that nothing is.
    var emptyMessage: String {
        switch self {
        case .workout:
            String(localized: "Finish a workout session and it will be here to share.", bundle: .app, locale: .app)
        case .meal:
            String(localized: "Log some food and the meal will be here to share.", bundle: .app, locale: .app)
        case .planner:
            String(localized: "Add a task or an event to the calendar and it will be here to share.", bundle: .app, locale: .app)
        }
    }
}

/// One row in the composer's picker.
///
/// The three sources are flattened to a title, a subtitle and an id so they can
/// share one list: what differs between a workout, a meal and a calendar entry
/// is where the row came from, not how it is drawn.
nonisolated struct PostCandidate: Identifiable, Hashable, Sendable {
    let kind: PostKind
    /// The backend id of the thing being posted, which is all the create
    /// request carries besides the caption.
    let sourceID: Int
    let title: String
    let subtitle: String
    /// The day it happened, so the composer can offer one day at a time
    /// instead of a list of everything ever recorded.
    let day: Date?

    init(
        kind: PostKind,
        sourceID: Int,
        title: String,
        subtitle: String,
        day: Date? = nil
    ) {
        self.kind = kind
        self.sourceID = sourceID
        self.title = title
        self.subtitle = subtitle
        self.day = day
    }

    /// Unique across sources: two different kinds can hold the same id, since
    /// each is numbered by its own table.
    var id: String { "\(kind.apiValue)-\(sourceID)" }
}

/// A backend id, wrapped so a screen can drive a share sheet from it.
///
/// Conforming `Int` to `Identifiable` would make every integer in the app
/// identifiable, which is why each share button carries one of these instead.
nonisolated struct SharedPostSource: Identifiable, Hashable, Sendable {
    let id: Int
}
