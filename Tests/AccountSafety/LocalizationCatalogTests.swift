import Foundation
import XCTest
@testable import AccountSafety

/// Whether every string the app shows exists in every language it offers.
///
/// A missing translation does not fail anywhere else: the lookup quietly
/// returns the English key, so a Japanese screen with one English button in
/// it looks finished to anyone who does not read Japanese. Placeholders are
/// worse -- a translation that drops a `%lld` prints the wrong number, and one
/// that adds a `%@` crashes. These read the catalog itself, then compile it
/// with the same tool Xcode uses and look strings up the way the app does.
final class LocalizationCatalogTests: XCTestCase {
    private static let translatedLanguages = AppLanguage.allCases
        .filter { $0 != .english }
        .map(\.rawValue)

    /// CLDR plural categories each language needs a form for.
    private static let pluralCategories: [String: Set<String>] = [
        "en": ["one", "other"], "es": ["one", "other"], "fr": ["one", "other"],
        "pt-BR": ["one", "other"], "de": ["one", "other"], "hi": ["one", "other"],
        "ru": ["one", "few", "many", "other"],
        "ar": ["zero", "one", "two", "few", "many", "other"],
        "ja": ["other"], "zh-Hans": ["other"],
    ]

    private func repository() throws -> URL {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"],
                                 "run through Scripts/test-account-safety.sh")
        return URL(fileURLWithPath: root)
    }

    private func catalogURL(_ name: String) throws -> URL {
        try repository().appendingPathComponent("IOS Frontend/IOS Frontend/\(name).xcstrings")
    }

    private func catalog(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: catalogURL(name))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func entries(_ name: String) throws -> [String: [String: Any]] {
        try XCTUnwrap(catalog(name)["strings"] as? [String: [String: Any]])
    }

    /// Every string that needs translating, with its localizations.
    private func translatable(_ name: String) throws -> [(key: String, localizations: [String: Any])] {
        try entries(name).compactMap { key, entry in
            if entry["shouldTranslate"] as? Bool == false { return nil }
            return (key, entry["localizations"] as? [String: Any] ?? [:])
        }
        .sorted { $0.key < $1.key }
    }

    /// Every finished value of one localization: one string, or one per plural form.
    private func values(of localization: Any?) -> [String: String]? {
        guard let localization = localization as? [String: Any] else { return nil }
        if let unit = localization["stringUnit"] as? [String: Any] {
            guard unit["state"] as? String == "translated", let value = unit["value"] as? String else {
                return nil
            }
            return ["": value]
        }
        guard let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: Any] else {
            return nil
        }
        var forms: [String: String] = [:]
        for (category, form) in plural {
            guard let unit = (form as? [String: Any])?["stringUnit"] as? [String: Any],
                  unit["state"] as? String == "translated",
                  let value = unit["value"] as? String else { return nil }
            forms[category] = value
        }
        return forms
    }

    /// The format arguments a string consumes, ignoring position markers.
    private func placeholders(in string: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:lld|ld|lu|llu|d|i|u|lf|f|@|%)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(string.startIndex..., in: string)
        return regex.matches(in: string, range: range)
            .map { (string as NSString).substring(with: $0.range) }
            .map { $0.replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression) }
            .filter { $0 != "%%" }
            .sorted()
    }

    // MARK: - Coverage

    func testTheCatalogIsInEnglishAndOffersEveryLanguage() throws {
        let catalog = try catalog("Localizable")
        XCTAssertEqual(catalog["sourceLanguage"] as? String, "en")
        var seen = Set<String>()
        for entry in try entries("Localizable").values {
            seen.formUnion((entry["localizations"] as? [String: Any] ?? [:]).keys)
        }
        XCTAssertEqual(seen.subtracting(["en"]), Set(Self.translatedLanguages),
                       "the catalog's languages must be exactly the ones Settings offers")
        XCTAssertGreaterThan(try translatable("Localizable").count, 500,
                             "the catalog looks empty; was it synced from the build?")
    }

    func testEveryStringIsTranslatedIntoEveryLanguage() throws {
        let strings = try translatable("Localizable")
        for language in Self.translatedLanguages {
            let missing = strings.filter { values(of: $0.localizations[language]) == nil }.map(\.key)
            XCTAssertTrue(
                missing.isEmpty,
                "\(missing.count) strings have no finished \(language) translation: "
                    + missing.prefix(15).map { "\"\($0)\"" }.joined(separator: ", ")
            )
        }
    }

    func testNoStringIsLeftStale() throws {
        // A stale entry is one the source no longer uses. Harmless at runtime,
        // but it means the catalog was not synced after the code changed --
        // which is also how a new string goes missing from it.
        let stale = try entries("Localizable")
            .filter { $0.value["extractionState"] as? String == "stale" }
            .map(\.key)
        XCTAssertTrue(stale.isEmpty, "stale catalog entries: \(stale.prefix(15))")
    }

    func testPermissionPromptsAreTranslated() throws {
        let strings = try translatable("InfoPlist")
        let keys = Set(strings.map(\.key))
        for required in [
            "NSCameraUsageDescription", "NSMicrophoneUsageDescription",
            "NSLocationWhenInUseUsageDescription", "NSMotionUsageDescription",
            "NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription",
        ] {
            XCTAssertTrue(keys.contains(required), "\(required) is not in InfoPlist.xcstrings")
        }
        for language in Self.translatedLanguages {
            for string in strings {
                XCTAssertNotNil(values(of: string.localizations[language]),
                                "\(string.key) has no \(language) translation")
            }
        }
    }

    // MARK: - Correctness

    func testTranslationsKeepEveryPlaceholder() throws {
        for (key, localizations) in try translatable("Localizable") {
            let expected = placeholders(in: key)
            for language in AppLanguage.allCases.map(\.rawValue) {
                guard let forms = values(of: localizations[language]) else { continue }
                for (category, value) in forms {
                    // The zero, one and two forms may spell their number out
                    // ("إدخالان", "one day") and drop only the count; every
                    // other placeholder must survive. Positional arguments
                    // make the skipped one safe.
                    let got = placeholders(in: value)
                    let counts = expected.filter { ["%lld", "%ld", "%d", "%i", "%u", "%lu", "%llu"].contains($0) }
                    let spelledOut = ["zero", "one", "two"].contains(category) && !counts.isEmpty
                        && got == expected.filter { !counts.contains($0) }
                    if spelledOut { continue }
                    XCTAssertEqual(got, expected,
                                   "\(language) \(category) for \"\(key)\" is \"\(value)\"")
                }
            }
        }
    }

    func testPluralFormsMatchEachLanguagesRules() throws {
        for (key, localizations) in try translatable("Localizable") {
            for (language, localization) in localizations {
                guard let forms = values(of: localization), forms[""] == nil,
                      let required = Self.pluralCategories[language] else { continue }
                let have = Set(forms.keys)
                XCTAssertTrue(required.isSubset(of: have),
                              "\(language) \"\(key)\" lacks plural forms \(required.subtracting(have))")
                XCTAssertTrue(have.isSubset(of: required.union(["zero", "one", "two"])),
                              "\(language) \"\(key)\" has plural forms the language does not use: \(have)")
            }
        }
    }

    func testEachLanguageIsWrittenInItsOwnScript() throws {
        // A translation pass that copied the English through would pass every
        // check above. Most strings in these languages contain at least one
        // character of their own script; brand names and units may not.
        let scripts: [String: ClosedRange<UnicodeScalar>] = [
            "ar": "\u{0600}"..."\u{06FF}", "hi": "\u{0900}"..."\u{097F}",
            "ru": "\u{0400}"..."\u{04FF}", "ja": "\u{3040}"..."\u{30FF}",
            "zh-Hans": "\u{4E00}"..."\u{9FFF}",
        ]
        let strings = try translatable("Localizable").filter { $0.key.split(separator: " ").count >= 3 }
        for (language, range) in scripts {
            let written = strings.filter { string in
                values(of: string.localizations[language])?.values.contains { value in
                    value.unicodeScalars.contains { range.contains($0) }
                } ?? false
            }
            XCTAssertGreaterThan(Double(written.count), Double(strings.count) * 0.95,
                                 "\(language) translations are not in their script")
        }
    }

    func testShortLabelsStayShort() throws {
        // Buttons, tabs and badges are laid out for a short word. A label
        // translated as a sentence clips or wraps the control around it.
        // German and Russian legitimately run long ("Lebensmittel
        // hinzufügen" for "Add Food"), so this only catches the runaway
        // case; whether a long label fits is checked on screen.
        for (key, localizations) in try translatable("Localizable") where key.count <= 16 {
            let limit = max(key.count * 3, key.count + 20)
            for language in Self.translatedLanguages {
                for value in (values(of: localizations[language]) ?? [:]).values where value.count > limit {
                    XCTFail("\(language) \"\(key)\" became \(value.count) characters: \"\(value)\"")
                }
            }
        }
    }

    func testAppStringsAreLookedUpInTheChosenLanguage() throws {
        // `String(localized:)` without `bundle: .app` reads Bundle.main, which
        // keeps the launch language until the next launch; without
        // `locale: .app` its plural forms follow that language's rules -- "5
        // подхода" for "5 подходов". Both are invisible in English.
        //
        // Counted rather than parsed: every lookup must carry both, so a file
        // has as many of each as it has lookups. Comments are left out.
        let sources = try repository().appendingPathComponent("IOS Frontend/IOS Frontend")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        func count(_ pattern: String, in text: String) -> Int {
            let regex = try! NSRegularExpression(pattern: pattern)
            return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        }
        var offenders: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let code = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let lookups = count(#"String\(\s*localized:"#, in: code)
            let bundles = count(#"bundle: \.app\b"#, in: code)
            let locales = count(#"bundle: \.app,\s*locale: \.app\b"#, in: code)
            if lookups != bundles || bundles != locales {
                offenders.append("\(file.lastPathComponent): \(lookups) lookups, \(bundles) with bundle, \(locales) with locale")
            }
            if code.contains("NSLocalizedString(") {
                offenders.append("\(file.lastPathComponent): NSLocalizedString")
            }
        }
        XCTAssertTrue(offenders.isEmpty, "lookups ignore the chosen language: \(offenders)")
    }

    // MARK: - At runtime

    /// The catalog compiled by the tool Xcode runs, into a folder of `.lproj`s.
    private func compiledCatalog() throws -> Bundle {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rytivo-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: output) }
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = ["xcstringstool", "compile", try catalogURL("Localizable").path,
                             "--output-directory", output.path]
        try compile.run()
        compile.waitUntilExit()
        XCTAssertEqual(compile.terminationStatus, 0, "xcstringstool could not compile the catalog")
        return try XCTUnwrap(Bundle(path: output.path))
    }

    func testEveryLanguageCompilesAndIsFoundAtRuntime() throws {
        let compiled = try compiledCatalog()
        let entries = try entries("Localizable")
        for language in AppLanguage.allCases {
            let lproj = try XCTUnwrap(compiled.path(forResource: language.rawValue, ofType: "lproj"),
                                      "no \(language.rawValue).lproj was compiled")
            let bundle = try XCTUnwrap(Bundle(path: lproj))
            guard language != .english else { continue }
            for key in ["Language", "System Default", "Settings"] {
                let localization = (entries[key]?["localizations"] as? [String: Any])?[language.rawValue]
                let expected = try XCTUnwrap(values(of: localization)?[""], "\(key) in \(language)")
                XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), expected)
            }
        }
    }

    func testSwitchingLanguageChangesStringsWithoutRelaunching() throws {
        let compiled = try compiledCatalog()
        let suite = "rytivo.catalog.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let localization = AppLocalization(
            settings: AppLanguageSettings(defaults: defaults, domainName: suite),
            resources: compiled
        )

        var seen: [AppLanguage: String] = [:]
        for language in AppLanguage.allCases {
            localization.select(.language(language))
            seen[language] = String(localized: "Language", bundle: localization.bundle)
        }
        XCTAssertEqual(seen[.english], "Language")
        for language in AppLanguage.allCases where language != .english {
            XCTAssertNotEqual(seen[language], "Language", "\(language) still shows English")
        }

        // And an interpolated string keeps its argument in every language.
        for language in AppLanguage.allCases {
            localization.select(.language(language))
            let name = language.nativeName
            let detail = String(localized: "System Default · \(name)", bundle: localization.bundle)
            XCTAssertTrue(detail.contains(name), "\(language): \(detail)")
        }
    }

    func testTheRouteDoesNotDependOnTheLanguage() throws {
        // Tab titles are translated; where a destination goes must not be.
        let compiled = try compiledCatalog()
        let suite = "rytivo.route.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let localization = AppLocalization(
            settings: AppLanguageSettings(defaults: defaults, domainName: suite),
            resources: compiled
        )
        let destinations: [RepbaseDestination] = [.workouts, .workoutDay(.monday), .food, .planner, .social, .account]
        let english = destinations.map { RepbaseRoute(for: $0).tab }
        for language in AppLanguage.allCases {
            localization.select(.language(language))
            XCTAssertEqual(destinations.map { RepbaseRoute(for: $0).tab }, english, "\(language)")
        }
    }
}
