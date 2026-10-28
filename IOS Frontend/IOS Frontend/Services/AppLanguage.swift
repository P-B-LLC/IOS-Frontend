//
//  AppLanguage.swift
//  IOS Frontend
//
//  Which language Rytivo speaks, and how that is decided.
//
//  Foundation only, so the account-safety package can copy this file in on
//  its own and test the rules without a simulator.
//

import Foundation

/// The languages Rytivo is translated into.
///
/// The raw values are the `.lproj` names the string catalog compiles to, so a
/// case is also the folder its translations are read from.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Hashable, Sendable {
    // First on purpose: it is what an unmatched device falls back to, and
    // `bestMatch` hands this order to the system matcher.
    case english = "en"
    case spanish = "es"
    case chineseSimplified = "zh-Hans"
    case hindi = "hi"
    case arabic = "ar"
    case french = "fr"
    case portugueseBrazil = "pt-BR"
    case russian = "ru"
    case japanese = "ja"
    case german = "de"

    static let fallback = AppLanguage.english

    var id: String { rawValue }

    /// The language's name for itself.
    ///
    /// Never translated: somebody who opened the list because they cannot
    /// read the current language has to be able to find their own in it.
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .chineseSimplified: return "简体中文"
        case .hindi: return "हिन्दी"
        case .arabic: return "العربية"
        case .french: return "Français"
        case .portugueseBrazil: return "Português (Brasil)"
        case .russian: return "Русский"
        case .japanese: return "日本語"
        case .german: return "Deutsch"
        }
    }

    var isRightToLeft: Bool { self == .arabic }

    /// The first of `preferredLanguages` that Rytivo is translated into,
    /// otherwise English.
    ///
    /// Matched by the same rules iOS uses to pick a bundle's localization, so
    /// "es-MX" finds Spanish, "zh-CN" finds Simplified Chinese and "pt-PT"
    /// finds Brazilian Portuguese, while "zh-TW" -- Traditional script -- is
    /// not quietly handed Simplified and falls through to the next language
    /// the person listed.
    static func bestMatch(for preferredLanguages: [String]) -> AppLanguage {
        let matched = Bundle.preferredLocalizations(
            from: allCases.map(\.rawValue),
            forPreferences: preferredLanguages
        )
        return matched.first.flatMap(AppLanguage.init(rawValue:)) ?? fallback
    }
}

/// What somebody chose in Settings: follow the iPhone, or one language.
nonisolated enum AppLanguagePreference: Hashable, Sendable {
    case system
    case language(AppLanguage)

    private static let systemValue = "system"

    init(storedValue: String?) {
        if let storedValue, let language = AppLanguage(rawValue: storedValue) {
            self = .language(language)
        } else {
            self = .system
        }
    }

    var storedValue: String {
        switch self {
        case .system: return Self.systemValue
        case .language(let language): return language.rawValue
        }
    }
}

/// Reads and writes the language preference.
///
/// A chosen language is also written to `AppleLanguages` in this app's own
/// domain. That is where iOS keeps the per-app language from
/// Settings > Rytivo > Language, so the next launch starts in the chosen
/// language everywhere this app cannot reach by itself: permission prompts,
/// system pickers and `Locale.current`. Choosing System Default removes it
/// again, which is exactly what resetting it in iOS Settings does.
nonisolated struct AppLanguageSettings {
    static let preferenceKey = "rytivo.language"
    static let appleLanguagesKey = "AppleLanguages"

    let defaults: UserDefaults
    /// The persistent domain `defaults` writes to, so `AppleLanguages` can be
    /// read from this app's own settings rather than through the search list,
    /// which also returns the device-wide value.
    let domainName: String

    init(defaults: UserDefaults = .standard, domainName: String? = Bundle.main.bundleIdentifier) {
        self.defaults = defaults
        self.domainName = domainName ?? ""
    }

    var preference: AppLanguagePreference {
        AppLanguagePreference(storedValue: defaults.string(forKey: Self.preferenceKey))
    }

    func setPreference(_ preference: AppLanguagePreference) {
        defaults.set(preference.storedValue, forKey: Self.preferenceKey)
        switch preference {
        case .system:
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        case .language(let language):
            defaults.set([language.rawValue], forKey: Self.appleLanguagesKey)
        }
    }

    /// The languages iOS would give this app on its own.
    ///
    /// Read through the search list, so a per-app language set in iOS
    /// Settings comes first and the device's list otherwise. Only meaningful
    /// while the preference is `.system`: a chosen language has written its
    /// own entry over the top. Read from defaults rather than
    /// `Locale.preferredLanguages`, which keeps whatever the process launched
    /// with after System Default removes that entry.
    var systemLanguages: [String] {
        defaults.stringArray(forKey: Self.appleLanguagesKey) ?? Locale.preferredLanguages
    }

    /// The language to show, given the languages iOS reports for this app.
    func resolvedLanguage(systemLanguages: [String]) -> AppLanguage {
        switch preference {
        case .system: return AppLanguage.bestMatch(for: systemLanguages)
        case .language(let language): return language
        }
    }

    /// Lets a change made in iOS Settings win over an older choice made here.
    ///
    /// Picking a language in Settings > Rytivo > Language rewrites the same
    /// `AppleLanguages` entry this app writes, then relaunches it. Without
    /// this, the stale choice stored here would put the old language straight
    /// back and that iOS screen would appear not to work. When the entry no
    /// longer says what this app last wrote, somebody else changed it, so the
    /// preference goes back to following the system -- which now means
    /// whatever they picked there.
    func reconcileWithSystemSettings() {
        guard case .language(let language) = preference else { return }
        let written = defaults.persistentDomain(forName: domainName)?[Self.appleLanguagesKey] as? [String]
        if written?.first != language.rawValue {
            defaults.set(AppLanguagePreference.system.storedValue, forKey: Self.preferenceKey)
        }
    }
}
