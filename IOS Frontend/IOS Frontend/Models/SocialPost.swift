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
    /// Whether the author showed what they lifted. False means the numbers
    /// were held back — which is a different thing from a bodyweight session,
    /// where there were none to show.
    var showsWeights: Bool = true
    /// Whether the reader wrote it. Offering to save your own workout back
    /// into your own workouts is not an offer worth making.
    var viewerIsAuthor: Bool = false
    /// The original, when this is a repost.
    var repostOf: RepostedPost?

    /// Whether this post offers a workout the reader could take for
    /// themselves. Their own is already theirs, and a workout with no
    /// exercises recorded is nothing to save.
    var offersWorkoutToSave: Bool {
        guard !viewerIsAuthor else { return false }
        return !(displayed.workout?.exercises.isEmpty ?? true)
    }

    /// Whether this post offers a meal the reader could keep. Their own is
    /// already theirs, and a meal with no food in it is nothing to save.
    var offersMealToSave: Bool {
        guard !viewerIsAuthor else { return false }
        return !(displayed.meal?.entries.isEmpty ?? true)
    }

    /// Whether this post can be reported or its author blocked. Neither is
    /// something to offer about yourself.
    var offersModeration: Bool { !viewerIsAuthor }

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

/// What saving somebody's posted meal produced.
///
/// Carries the name for the same reason the workout one does: saved meal
/// names are unique per person, and everyone has a "Meal 1", so a copy very
/// often lands under a different name and the app has to say which.
nonisolated struct SavedMealOutcome: Equatable, Hashable, Sendable {
    let name: String
    let itemCount: Int
    let wasRenamed: Bool

    var message: String {
        let items = itemCount == 1 ? "1 item" : "\(itemCount) items"
        if wasRenamed {
            return "Saved as \"\(name)\" — \(items). You already had one by its own name."
        }
        return "Saved \"\(name)\" to your meals — \(items)."
    }
}

/// Somebody this reader has blocked.
///
/// `id` is the block's own id, not the person's: lifting a block is a delete
/// of this row, and the person is carried alongside so a list of them is not
/// a profile fetch each.
nonisolated struct BlockedPerson: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let person: PostAuthor
}

/// Why somebody is reporting a post.
///
/// A fixed list, matching the server's: reports exist to be triaged and
/// counted, which free text does not allow. `detail` on the request is where
/// anything this list does not cover goes.
nonisolated enum PostReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam
    case harassment
    case hate
    case violence
    case nudity
    case harm
    case advice
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: return "Spam or misleading"
        case .harassment: return "Harassment or bullying"
        case .hate: return "Hate speech"
        case .violence: return "Violence or threats"
        case .nudity: return "Nudity or sexual content"
        case .harm: return "Promotes self-harm or disordered eating"
        case .advice: return "Dangerous or false advice"
        case .other: return "Something else"
        }
    }

    /// Only the open-ended one asks for more. Making everyone explain a plain
    /// "spam" would be a form where a tap would do.
    var invitesDetail: Bool { self == .other }
}

/// What saving somebody's posted workout produced.
///
/// The name is carried because it is not always the one on the post: workout
/// names are unique per person, so a copy of a "Push Day" you already have
/// arrives under a name saying where it came from, and the app has to be able
/// to tell you which one you got.
nonisolated struct SavedWorkoutOutcome: Equatable, Hashable, Sendable {
    let name: String
    let exerciseCount: Int
    let wasRenamed: Bool

    var message: String {
        let exercises = exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
        if wasRenamed {
            return "Saved as \"\(name)\" — \(exercises). You already had one by its own name."
        }
        return "Saved \"\(name)\" to your workouts — \(exercises)."
    }
}
