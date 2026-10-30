import Foundation
import Observation
import XCTest
@testable import AccountSafety

/// Which language the app shows, and what makes it change.
///
/// The rules, in order: a choice made in Settings wins; otherwise the
/// iPhone's languages are walked in the order the person listed them; and a
/// list with nothing Rytivo speaks gets English. A choice survives relaunch,
/// System Default undoes it, and a newer choice made in iOS Settings beats an
/// older one made here.
final class AppLanguageTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "rytivo.language.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var settings: AppLanguageSettings {
        AppLanguageSettings(defaults: defaults, domainName: suiteName)
    }

    /// What this app wrote, read from its own domain rather than through the
    /// search list, which would also return the Mac's own languages.
    private var writtenAppleLanguages: [String]? {
        defaults.persistentDomain(forName: suiteName)?[AppLanguageSettings.appleLanguagesKey] as? [String]
    }

    // MARK: - Detecting the iPhone's language

    func testEverySupportedDeviceLanguageIsDetected() {
        let cases: [(String, AppLanguage)] = [
            ("en-US", .english), ("es-MX", .spanish), ("zh-Hans-CN", .chineseSimplified),
            ("zh-CN", .chineseSimplified), ("hi-IN", .hindi), ("ar-SA", .arabic),
            ("fr-CA", .french), ("pt-BR", .portugueseBrazil), ("ru-RU", .russian),
            ("ja-JP", .japanese), ("de-AT", .german),
        ]
        for (device, expected) in cases {
            XCTAssertEqual(AppLanguage.bestMatch(for: [device]), expected, device)
        }
    }

    func testRegionalVariantsFindTheirLanguage() {
        XCTAssertEqual(AppLanguage.bestMatch(for: ["pt-PT"]), .portugueseBrazil)
        XCTAssertEqual(AppLanguage.bestMatch(for: ["en-GB"]), .english)
        XCTAssertEqual(AppLanguage.bestMatch(for: ["es-419"]), .spanish)
    }

    func testAnUnsupportedLanguageFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.bestMatch(for: ["ko-KR"]), .english)
        XCTAssertEqual(AppLanguage.bestMatch(for: []), .english)
        XCTAssertEqual(AppLanguage.fallback, .english)
    }

    func testTraditionalChineseIsNotHandedSimplified() {
        // A different script, not a regional spelling: iOS itself would not
        // pick a zh-Hans bundle for it, and neither does this.
        XCTAssertEqual(AppLanguage.bestMatch(for: ["zh-Hant-TW"]), .english)
        XCTAssertEqual(AppLanguage.bestMatch(for: ["zh-TW", "ja-JP"]), .japanese)
    }

    func testTheDeviceListIsWalkedInOrder() {
        XCTAssertEqual(AppLanguage.bestMatch(for: ["ko-KR", "de-DE", "fr-FR"]), .german)
        XCTAssertEqual(AppLanguage.bestMatch(for: ["fr-FR", "de-DE"]), .french)
    }

    // MARK: - First launch

    func testFirstLaunchFollowsTheSystem() {
        XCTAssertEqual(settings.preference, .system)
        XCTAssertEqual(settings.resolvedLanguage(systemLanguages: ["fr-FR", "en"]), .french)
        XCTAssertEqual(settings.resolvedLanguage(systemLanguages: ["ko-KR"]), .english)
        XCTAssertNil(writtenAppleLanguages, "following the system must not write over it")
    }

    func testAPerAppLanguageFromIOSSettingsCountsAsTheSystem() {
        // Settings > Rytivo > Language writes AppleLanguages into the app's
        // own domain. With no choice made in the app, that is what it follows.
        defaults.set(["ja"], forKey: AppLanguageSettings.appleLanguagesKey)
        XCTAssertEqual(settings.resolvedLanguage(systemLanguages: settings.systemLanguages), .japanese)
    }

    // MARK: - Choosing a language

    func testAChoiceOverridesTheSystem() {
        settings.setPreference(.language(.japanese))
        XCTAssertEqual(settings.preference, .language(.japanese))
        XCTAssertEqual(settings.resolvedLanguage(systemLanguages: ["fr-FR"]), .japanese)
    }

    func testAChoiceIsWhatTheNextLaunchStartsIn() {
        settings.setPreference(.language(.arabic))
        // Mirrored where iOS reads a per-app language, so permission prompts
        // and Locale.current agree with the app after relaunching.
        XCTAssertEqual(writtenAppleLanguages, ["ar"])
    }

    func testAChoiceSurvivesRelaunching() {
        settings.setPreference(.language(.hindi))
        let relaunched = AppLanguageSettings(
            defaults: UserDefaults(suiteName: suiteName)!,
            domainName: suiteName
        )
        relaunched.reconcileWithSystemSettings()
        XCTAssertEqual(relaunched.preference, .language(.hindi))
        XCTAssertEqual(relaunched.resolvedLanguage(systemLanguages: ["en-US"]), .hindi)
    }

    func testSystemDefaultUndoesAChoice() {
        settings.setPreference(.language(.german))
        settings.setPreference(.system)
        XCTAssertEqual(settings.preference, .system)
        XCTAssertNil(writtenAppleLanguages, "System Default must hand AppleLanguages back to iOS")
        XCTAssertEqual(settings.resolvedLanguage(systemLanguages: ["es-ES"]), .spanish)
    }

    func testANewerChoiceInIOSSettingsWins() {
        settings.setPreference(.language(.german))
        // What Settings > Rytivo > Language does before relaunching the app.
        defaults.set(["fr"], forKey: AppLanguageSettings.appleLanguagesKey)
        settings.reconcileWithSystemSettings()
        XCTAssertEqual(settings.preference, .system)
        XCTAssertEqual(settings.resolvedLanguage(systemLanguages: settings.systemLanguages), .french)
    }

    func testResettingTheLanguageInIOSSettingsIsHonoured() {
        settings.setPreference(.language(.russian))
        defaults.removeObject(forKey: AppLanguageSettings.appleLanguagesKey)
        settings.reconcileWithSystemSettings()
        XCTAssertEqual(settings.preference, .system)
    }

    func testAnUnknownStoredValueMeansSystem() {
        defaults.set("tlh", forKey: AppLanguageSettings.preferenceKey)
        XCTAssertEqual(settings.preference, .system)
        XCTAssertEqual(AppLanguagePreference(storedValue: nil), .system)
        for language in AppLanguage.allCases {
            let preference = AppLanguagePreference.language(language)
            XCTAssertEqual(AppLanguagePreference(storedValue: preference.storedValue), preference)
        }
    }

    // MARK: - The list in Settings

    func testTenLanguagesEachNamedInItself() {
        XCTAssertEqual(AppLanguage.allCases.count, 10)
        XCTAssertEqual(AppLanguage.allCases.first, .english)
        let names = AppLanguage.allCases.map(\.nativeName)
        XCTAssertEqual(Set(names).count, names.count, "two languages share a name")
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(AppLanguage.allCases.filter(\.isRightToLeft), [.arabic])
    }

    // MARK: - Switching while the app is open

    func testSelectingSwitchesImmediatelyAndKeepsTheRegion() {
        let localization = AppLocalization(settings: settings)
        localization.select(.language(.german))
        XCTAssertEqual(localization.language, .german)
        XCTAssertEqual(localization.preference, .language(.german))
        XCTAssertEqual(localization.locale.language.languageCode?.identifier, "de")
        XCTAssertEqual(
            localization.locale.region,
            Locale.autoupdatingCurrent.region,
            "changing language must not change the person's region"
        )
    }

    func testSelectingNotifiesObservers() {
        let localization = AppLocalization(settings: settings)
        let changed = expectation(description: "a view reading the language is told it changed")
        withObservationTracking {
            _ = localization.bundle
        } onChange: {
            changed.fulfill()
        }
        localization.select(.language(.japanese))
        wait(for: [changed], timeout: 1)
    }

    func testAChoiceIsRestoredOnTheNextLaunch() {
        AppLocalization(settings: settings).select(.language(.spanish))
        let relaunched = AppLocalization(settings: settings)
        XCTAssertEqual(relaunched.language, .spanish)
        XCTAssertEqual(relaunched.preference, .language(.spanish))
    }

    func testSystemDefaultReturnsToTheDeviceLanguage() {
        let localization = AppLocalization(settings: settings)
        localization.select(.language(.russian))
        localization.select(.system)
        XCTAssertEqual(localization.preference, .system)
        XCTAssertEqual(localization.language, AppLanguage.bestMatch(for: settings.systemLanguages))
    }
}
