//
//  AppLocalization.swift
//  IOS Frontend
//
//  The language the interface is in right now, readable from anywhere.
//

import Foundation
import Observation

/// Holds the language currently on screen and switches it without a relaunch.
///
/// iOS fixes a process's language when it launches, so a choice made in
/// Settings would otherwise wait for the next launch. Two things carry it
/// sooner. SwiftUI's own strings follow the `locale` this puts in the
/// environment at the root. Everything built as a `String` first -- error
/// messages, model names, formatted dates -- is looked up in `bundle`, the
/// chosen language's `.lproj`, through
/// `String(localized: "…", bundle: .app, locale: .app)`. The locale matters as
/// much as the bundle: plural forms are chosen by its rules, so without it a
/// Russian "5 sets" takes the form English rules pick.
///
/// Observable by hand rather than with the macro, because model code that is
/// `nonisolated` reads this, and the macro's storage is only safe on one
/// actor. Every read registers with the observation registrar, so a view body
/// that builds a string from it is redrawn when the language changes, without
/// tearing down the screen somebody is looking at. Changes happen on the main
/// actor; the lock is for the reads that do not.
nonisolated final class AppLocalization: Observable, @unchecked Sendable {
    static let shared = AppLocalization()

    private struct Current {
        var preference: AppLanguagePreference
        var language: AppLanguage
        var bundle: Bundle
        var locale: Locale
    }

    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private let settings: AppLanguageSettings
    /// Where the compiled `.lproj` folders are. The app's own bundle, except
    /// in tests, which compile the catalog somewhere of their own.
    private let resources: Bundle
    private var current: Current

    init(settings: AppLanguageSettings = AppLanguageSettings(), resources: Bundle = .main) {
        settings.reconcileWithSystemSettings()
        self.settings = settings
        self.resources = resources
        let preference = settings.preference
        let language = settings.resolvedLanguage(systemLanguages: settings.systemLanguages)
        current = Self.current(preference: preference, language: language, resources: resources)
    }

    var preference: AppLanguagePreference { read(\.preference) }
    var language: AppLanguage { read(\.language) }
    /// Where user-facing strings are looked up. Named `Bundle.app` below.
    var bundle: Bundle { read(\.bundle) }
    /// The chosen language with the person's own region, calendar and clock.
    var locale: Locale { read(\.locale) }

    /// What System Default would show right now, or nil when that cannot be
    /// told.
    var systemLanguage: AppLanguage? {
        registrar.access(self, keyPath: \.language)
        guard case .system = preference else {
            // A chosen language has written over the per-app entry, so this
            // app's own defaults -- and Locale.preferredLanguages, which reads
            // them -- now answer with that choice. The device-wide list is
            // what iOS consults next. Unknown is better than naming the
            // chosen language as the iPhone's.
            let global = CFPreferencesCopyValue(
                AppLanguageSettings.appleLanguagesKey as CFString,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? [String]
            return global.map(AppLanguage.bestMatch(for:))
        }
        return language
    }

    /// Saves the choice and switches every screen to it.
    func select(_ preference: AppLanguagePreference) {
        settings.setPreference(preference)
        let language = settings.resolvedLanguage(systemLanguages: settings.systemLanguages)
        registrar.withMutation(of: self, keyPath: \.language) {
            lock.withLock {
                current = Self.current(preference: preference, language: language, resources: resources)
            }
        }
    }

    private func read<Value>(_ keyPath: KeyPath<Current, Value>) -> Value {
        // Every property hangs off the one key: they only ever change together.
        registrar.access(self, keyPath: \.language)
        return lock.withLock { current[keyPath: keyPath] }
    }

    private static func current(
        preference: AppLanguagePreference,
        language: AppLanguage,
        resources: Bundle
    ) -> Current {
        Current(
            preference: preference,
            language: language,
            bundle: bundle(for: language, in: resources),
            locale: locale(for: language)
        )
    }

    /// The `.lproj` the string catalog compiled for `language`.
    ///
    /// English too, rather than `Bundle.main`: the main bundle answers in the
    /// language the process launched with, which after a switch to English
    /// is the one just left. Missing keys come back as the key, which is the
    /// English text, so a gap reads as English rather than as nothing.
    private static func bundle(for language: AppLanguage, in resources: Bundle) -> Bundle {
        resources.path(forResource: language.rawValue, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? resources
    }

    /// The person's own locale with only the language replaced, so names of
    /// days and months change while their region's separators, clock and
    /// first weekday stay as they set them.
    private static func locale(for language: AppLanguage) -> Locale {
        let base = Locale.autoupdatingCurrent
        var components = Locale.Components(locale: base)
        components.languageComponents = Locale.Language.Components(identifier: language.rawValue)
        // Replacing the language drops the region, so it is put back.
        components.region = base.region
        return Locale(components: components)
    }
}

extension Bundle {
    /// The bundle to look user-facing strings up in: the language chosen in
    /// Settings, which can differ from the one the process launched with.
    ///
    /// Always `String(localized: "…", bundle: .app, locale: .app)` for text
    /// shown to somebody. Plain `String(localized:)` reads `Bundle.main`, which
    /// only changes language at the next launch.
    nonisolated static var app: Bundle { AppLocalization.shared.bundle }
}

extension Locale {
    /// The locale to format user-facing dates with, and to choose plural
    /// forms by, for the same reason `Bundle.app` exists: `Locale.current` is
    /// fixed at launch.
    nonisolated static var app: Locale { AppLocalization.shared.locale }
}
