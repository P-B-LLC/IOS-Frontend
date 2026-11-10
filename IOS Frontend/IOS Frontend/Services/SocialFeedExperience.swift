//
//  SocialFeedExperience.swift
//  IOS Frontend
//
//  The switches for the new Social feed.
//

import Foundation

/// Whether the media-first feed is on, and whether its clips may start by
/// themselves.
///
/// Two switches, separate on purpose: the plan releases the new interface
/// and autoplay independently, so either can be held back or pulled without
/// the other. Both live in `UserDefaults`, which a launch argument can set
/// (`-social.newFeed YES`) for a tester before there is a screen for it.
///
/// Off by default. With it off the app requests, draws and plays exactly
/// what it did before.
nonisolated enum SocialFeedExperience {
    static let enabledKey = "social.newFeed"
    static let autoplayKey = "social.autoplay"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// On unless the reader turned it off: an unset key is "has not said".
    static var autoplayPreferred: Bool {
        UserDefaults.standard.object(forKey: autoplayKey) as? Bool ?? true
    }
}
