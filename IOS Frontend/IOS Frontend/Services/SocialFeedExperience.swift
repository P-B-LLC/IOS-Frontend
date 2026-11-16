//
//  SocialFeedExperience.swift
//  IOS Frontend
//
//  The switches for the new Social feed.
//

import Foundation

/// Which parts of the new Social the server has given this account.
///
/// Everything is off until the server says otherwise: a part the server does
/// not mention, an older server that has no such endpoint, and a first
/// launch with no connection all read as off.
nonisolated struct SocialFeatures: Codable, Equatable, Sendable {
    var newFeed = false
    var autoplay = false
    var measurement = false
    var sounds = false
    var takes = false

    static let off = SocialFeatures()
}

/// Whether the media-first feed is on, whether its clips may start by
/// themselves, and whether what is on screen is measured.
///
/// Separate switches on purpose: the plan releases the interface, autoplay
/// and measurement independently, so any one can be held back or pulled
/// without the others. The server decides, per account
/// (`GET social/features/`), asked on connecting and each time the app comes
/// to the front. A failed ask leaves the last answer standing, for at most a
/// day, so something pulled back does not linger on a phone that has stopped
/// hearing. Connecting afresh forgets it: with no answer, everything is off.
///
/// A launch argument (`-social.newFeed YES`) still overrides the first, for a
/// tester before their account has been invited. It changes what this app
/// draws, never what the server allows.
nonisolated enum SocialFeedExperience {
    static let enabledKey = "social.newFeed"
    static let autoplayKey = "social.autoplay"
    static let serverKey = "social.serverFeatures"
    static let serverDateKey = "social.serverFeaturesAt"

    /// How long the server's last answer stands in for a new one.
    static let serverAnswerLifetime: TimeInterval = 24 * 60 * 60

    /// What the server last said, if it said it recently enough.
    static func server(_ defaults: UserDefaults = .standard, now: Date = Date()) -> SocialFeatures {
        guard
            let data = defaults.data(forKey: serverKey),
            let asked = defaults.object(forKey: serverDateKey) as? Date,
            now.timeIntervalSince(asked) < serverAnswerLifetime,
            now.timeIntervalSince(asked) > -60,
            let features = try? JSONDecoder().decode(SocialFeatures.self, from: data)
        else { return .off }
        return features
    }

    static func remember(_ features: SocialFeatures, in defaults: UserDefaults = .standard, now: Date = Date()) {
        guard let data = try? JSONEncoder().encode(features) else { return }
        defaults.set(data, forKey: serverKey)
        defaults.set(now, forKey: serverDateKey)
    }

    /// Signing out, or signing in as somebody else: their answer is not the
    /// next account's.
    static func forget(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: serverKey)
        defaults.removeObject(forKey: serverDateKey)
    }

    static func isEnabled(_ defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        if let override = defaults.object(forKey: enabledKey) as? Bool { return override }
        return server(defaults, now: now).newFeed
    }

    static var isEnabled: Bool { isEnabled(.standard) }

    /// Clips start by themselves only when the server allows it and the
    /// reader has not turned it off. An unset preference is "has not said".
    static func autoplayPreferred(_ defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        guard server(defaults, now: now).autoplay else { return false }
        return defaults.object(forKey: autoplayKey) as? Bool ?? true
    }

    static var autoplayPreferred: Bool { autoplayPreferred(.standard) }

    /// Whether exposures are summed up and sent at all.
    static func measures(_ defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        server(defaults, now: now).measurement
    }

    static var measures: Bool { measures(.standard) }
}
