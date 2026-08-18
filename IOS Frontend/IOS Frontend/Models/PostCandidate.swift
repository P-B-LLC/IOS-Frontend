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
    let workoutName: String
    /// When it happened: the end of the session, or its start when it never
    /// recorded an end.
    let performedAt: Date
    let durationSeconds: Double?
    let routeDistanceKilometers: Double?

    var id: Int { sessionID }
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
        case .workout: "Workout"
        case .meal: "Food"
        case .planner: "Calendar"
        }
    }

    var symbol: String {
        switch self {
        case .workout: "dumbbell.fill"
        case .meal: "fork.knife"
        case .planner: "calendar"
        }
    }

    /// Says what would put something here, rather than only that nothing is.
    var emptyMessage: String {
        switch self {
        case .workout:
            "Finish a workout session and it will be here to share."
        case .meal:
            "Log some food and the meal will be here to share."
        case .planner:
            "Add a task or an event to the calendar and it will be here to share."
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
