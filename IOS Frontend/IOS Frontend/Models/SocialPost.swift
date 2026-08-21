//
//  SocialPost.swift
//  IOS Frontend
//
//  App-facing shapes for the feed. A post carries a copy of what was posted,
//  taken when it was posted, so a card still draws after the workout or meal
//  behind it has been deleted.
//

import Foundation

/// What a post is of.
///
/// An unrecognised kind is kept rather than rejected. The server may learn to
/// post something this build has never heard of, and the right answer then is
/// one card this app cannot draw, not a feed that fails to load.
nonisolated enum PostKind: Equatable, Hashable, Sendable {
    case workout
    case meal
    case planner
    /// Someone else's post, passed on. The only kind carrying no snapshot of
    /// its own: what it shows is the post it points at.
    case repost
    case unknown(String)

    init(_ raw: String) {
        switch raw {
        case "workout": self = .workout
        case "meal": self = .meal
        case "planner": self = .planner
        case "repost": self = .repost
        default: self = .unknown(raw)
        }
    }

    var apiValue: String {
        switch self {
        case .workout: "workout"
        case .meal: "meal"
        case .planner: "planner"
        case .repost: "repost"
        case .unknown(let raw): raw
        }
    }
}

nonisolated enum PostVisibility: String, CaseIterable, Identifiable, Sendable {
    case publicToAll = "public"
    case followers
    case privateToMe = "private"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publicToAll: "Everyone"
        case .followers: "Followers"
        case .privateToMe: "Only me"
        }
    }

    var symbol: String {
        switch self {
        case .publicToAll: "globe"
        case .followers: "person.2.fill"
        case .privateToMe: "lock.fill"
        }
    }

    var explanation: String {
        switch self {
        case .publicToAll: "Anyone on Repbase can see this."
        case .followers: "Only people who follow you."
        case .privateToMe: "Kept on your profile, shown to nobody else."
        }
    }
}

nonisolated struct PostAuthor: Equatable, Hashable, Sendable {
    let id: Int
    var username: String
    var firstName: String
    var lastName: String
    var photoURL: String?

    var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? username : full
    }

    var initials: String {
        let parts = [firstName, lastName].filter { !$0.isEmpty }
        guard !parts.isEmpty else { return String(username.prefix(1)).uppercased() }
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
    }
}

nonisolated struct PostExerciseLine: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    var name: String
    var setCount: Int
    var topSetWeightKg: Decimal?
    var topSetReps: Int?
}

nonisolated struct PostWorkoutSnapshot: Equatable, Hashable, Sendable {
    var title: String
    var workoutType: String?
    var performedAt: Date
    var durationSeconds: Int?
    var exerciseCount: Int
    var totalSetCount: Int
    var totalVolumeKg: Decimal?
    var routeDistanceKm: Decimal?
    var exercises: [PostExerciseLine]
}

nonisolated struct PostFoodLine: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    var name: String
    var servings: Decimal
    var totalCalories: Decimal
}

nonisolated struct PostMealSnapshot: Equatable, Hashable, Sendable {
    var name: String
    var date: String
    var totalCalories: Decimal
    var totalProteinGrams: Decimal
    var totalCarbohydrateGrams: Decimal
    var totalFatGrams: Decimal
    var entries: [PostFoodLine]
}

nonisolated struct PostPlannerSnapshot: Equatable, Hashable, Sendable {
    var kind: String
    var title: String
    var category: String
    var scheduledDate: String
    var scheduledTime: String?
    var isComplete: Bool
}

/// One post as the feed reads it.
///
/// The three snapshots sit side by side with exactly one filled in, matching
/// the contract. A build that meets a fourth kind draws nothing for that post
/// and everything for the rest of the page.
/// A picture chosen for a post, ready to send.
///
/// Base64 in JSON rather than multipart, matching the profile photo and the
/// contract: the generated client needs no separate upload path, and the photo
/// travels with the create so a post is never published without it.
nonisolated struct PostPhoto: Equatable, Hashable, Sendable {
    /// One of the types the contract accepts, e.g. "image/jpeg".
    let contentType: String
    /// The image bytes, base64 encoded, with no `data:` prefix.
    let base64: String
}

/// The post inside a repost.
///
/// A shape of its own rather than a `FeedPost` holding a `FeedPost`, which a
/// struct cannot do. It carries no engagement figures because none are its
/// own: liking a repost likes the repost, and the counts shown belong to
/// whichever card is on screen.
nonisolated struct RepostedPost: Equatable, Hashable, Sendable {
    let id: Int
    var author: PostAuthor
    var kind: PostKind
    var caption: String
    var imageURL: URL?
    var createdAt: Date
    var workout: PostWorkoutSnapshot?
    var meal: PostMealSnapshot?
    var planner: PostPlannerSnapshot?
}

nonisolated struct FeedPost: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    var author: PostAuthor
    var kind: PostKind
    var caption: String
    /// The attached photo, if the author chose one.
    var imageURL: URL?
    var visibility: PostVisibility
    var createdAt: Date
    var viewerFollowsAuthor: Bool
    /// Set only on your own posts: what this was made from.
    var sourceID: Int?
    var workout: PostWorkoutSnapshot?
    var meal: PostMealSnapshot?
    var planner: PostPlannerSnapshot?

    // What other people have done with it. Counted by the server, because a
    // client only ever sees the page in front of it.
    var likeCount: Int = 0
    var commentCount: Int = 0
    var repostCount: Int = 0
    /// Whether the person reading has already done it, so the buttons can be
    /// drawn in the right state on first paint.
    var viewerHasLiked: Bool = false
    var viewerHasReposted: Bool = false
    /// The original, when this is a repost.
    var repostOf: RepostedPost?

    /// Whether this build knows how to draw the post at all.
    ///
    /// A repost is drawable when the post underneath it is: it has no snapshot
    /// of its own and never will.
    var isRenderable: Bool {
        if let repostOf {
            return repostOf.workout != nil
                || repostOf.meal != nil
                || repostOf.planner != nil
        }
        return workout != nil || meal != nil || planner != nil
    }

    /// What the card actually draws — the original for a repost, itself
    /// otherwise. The engagement figures stay with `self` either way.
    var displayed: RepostedPost {
        repostOf ?? RepostedPost(
            id: id,
            author: author,
            kind: kind,
            caption: caption,
            imageURL: imageURL,
            createdAt: createdAt,
            workout: workout,
            meal: meal,
            planner: planner
        )
    }
}
