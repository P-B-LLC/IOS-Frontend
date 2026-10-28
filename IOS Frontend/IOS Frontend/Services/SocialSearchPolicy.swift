import Foundation

/// The existing API returns people and posts, not a separate hashtag index.
nonisolated enum SocialSearchScope: String, CaseIterable, Identifiable, Sendable {
    case people = "People"
    case posts = "Posts"

    var id: String { rawValue }
}

/// Prefixes give a new search a useful starting point without fighting the
/// reader's filter choice on every subsequent keystroke.
nonisolated enum SocialSearchPolicy {
    static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func preferredScope(
        for newQuery: String,
        previousQuery: String,
        currentScope: SocialSearchScope
    ) -> SocialSearchScope {
        let query = normalizedQuery(newQuery)
        guard !query.isEmpty else { return .people }
        let previousPrefix = normalizedQuery(previousQuery).first

        if query.first == "#", previousPrefix != "#" { return .posts }
        if query.first == "@", previousPrefix != "@" { return .people }
        return currentScope
    }
}
