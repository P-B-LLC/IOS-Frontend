//
//  ForYou.swift
//  IOS Frontend
//
//  What the For You page has picked up about the reader, what they have told
//  it, and the people suggested beside it.
//

import Foundation

/// One topic the For You page counts toward what the reader is shown.
nonisolated struct ForYouInterest: Identifiable, Equatable, Hashable, Sendable {
    let topic: String
    var label: String
    /// From 0 to 1: how much it counts.
    var strength: Double
    /// The reader picked it themselves -- in onboarding, on their profile or
    /// by adding it here -- rather than the page reading it into what they
    /// did.
    var declared: Bool

    var id: String { topic }
}

/// A topic that can be hidden or added, by its code and the name to show
/// for it.
nonisolated struct ForYouTopic: Identifiable, Equatable, Hashable, Sendable {
    let topic: String
    var label: String

    var id: String { topic }
}

/// The reader's say over their For You page, and what it is working from.
nonisolated struct ForYouPreferences: Equatable, Sendable {
    /// Off: the page stops using what the reader does and shows what is
    /// popular and new instead.
    var personalized: Bool
    /// Topic codes never to be shown, each one of `hideableTopics`.
    var hiddenTopics: [String]
    /// When the reader last started fresh, if ever.
    var historyClearedAt: Date?
    /// Strongest first. Empty when personalisation is off.
    var interests: [ForYouInterest]
    /// Every topic that may be hidden, in the order to offer them.
    var hideableTopics: [ForYouTopic]
    /// Topic codes the reader added as interests, each one of
    /// `addableTopics`. Never also hidden.
    var addedTopics: [String]
    /// Every topic that may be added, in the order to offer them: the broad
    /// ones, kinds of athlete, then the exercises posted most lately.
    var addableTopics: [ForYouTopic]

    func isHidden(_ topic: String) -> Bool {
        hiddenTopics.contains(topic)
    }

    func isAdded(_ topic: String) -> Bool {
        addedTopics.contains(topic)
    }
}

/// How a post left For You on this screen. Both take the card off with an
/// undo; they differ in how much of its author the page then shows.
nonisolated enum ForYouDismissal: Equatable, Sendable {
    case notInterested
    case fewerLikeThis
}

/// Somebody the reader might want to follow, and why.
nonisolated struct SuggestedPerson: Identifiable, Equatable, Hashable, Sendable {
    var person: PostAuthor
    /// A plain-string code -- engaged, mutual, similar, discipline,
    /// new_creator, popular -- or one added after this build.
    var reason: String
    /// The sentence to show under their name.
    var label: String

    var id: Int { person.id }
}
