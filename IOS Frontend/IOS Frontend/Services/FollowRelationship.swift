import Foundation

/// Where the signed-in person stands with somebody else, both ways round.
///
/// The two directions are kept apart on purpose, and so are the two places
/// they are shown. The button only ever says what *you* do -- follow, follow
/// back, request, or that you already follow -- and only acts on your side of
/// the relationship. Whether *they* follow you is shown beside it, as a label
/// rather than an action. One button carrying both facts is what makes other
/// apps' "Following" ambiguous: it hides whether the follow is returned.
nonisolated struct FollowRelationship: Hashable, Sendable {
    enum Outgoing: Hashable, Sendable {
        case none
        /// Asked a closed profile and waiting for an answer.
        case requested
        case following
    }

    var outgoing: Outgoing
    /// Nil when it is not known yet, which shows nothing rather than a guess.
    var followsViewer: Bool?
    /// A closed profile turns a follow into a request.
    var isPrivate: Bool

    enum Action: Hashable, Sendable {
        case follow
        /// They already follow you; following now makes it mutual.
        case followBack
        /// Their profile is closed, so following means asking.
        case request
        /// Already asked; tapping offers to withdraw the request.
        case requested
        /// Already following; tapping offers to unfollow, never does it alone.
        case following
    }

    var action: Action {
        switch outgoing {
        case .following: return .following
        case .requested: return .requested
        case .none:
            if isPrivate { return .request }
            return followsViewer == true ? .followBack : .follow
        }
    }

    enum Badge: Hashable, Sendable {
        case followsYou
        case mutual
    }

    /// What is shown beside the button about their side.
    var badge: Badge? {
        guard followsViewer == true else { return nil }
        return outgoing == .following ? .mutual : .followsYou
    }

    var isMutual: Bool { badge == .mutual }

    /// Whether the button's next tap is a change you should be asked about.
    /// Following is one tap and easy to undo; unfollowing a closed profile
    /// means asking again and waiting, so it is confirmed first.
    var confirmsBeforeLeaving: Bool { action == .following || action == .requested }

    /// The relationship as it will be once a follow tap is answered. A closed
    /// profile answers with a request, an open one with the follow itself.
    func afterFollowing(requested: Bool) -> FollowRelationship {
        var next = self
        next.outgoing = requested ? .requested : .following
        return next
    }

    func afterLeaving() -> FollowRelationship {
        var next = self
        next.outgoing = .none
        return next
    }
}
