import Foundation
import XCTest
@testable import AccountSafety

/// The exercise library in every language the app offers.
///
/// Names and steps come from the library file, not from code, so nothing
/// else notices when one goes untranslated: the lookup quietly answers in
/// English. These read `ExerciseLibrary.xcstrings` against the library the app
/// ships, then compile it with the tool Xcode uses and look names up the way
/// the app does.
final class ExerciseLibraryLocalizationTests: XCTestCase {
    private static let translatedLanguages = AppLanguage.allCases
        .filter { $0 != .english }
        .map(\.rawValue)

    private func repository() throws -> URL {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"],
                                 "run through Scripts/test-account-safety.sh")
        return URL(fileURLWithPath: root).appendingPathComponent("IOS Frontend/IOS Frontend")
    }

    private func shippedLibrary() throws -> ExerciseLibrary {
        let url = try repository().appendingPathComponent("Resources/ExerciseLibrary/exercise_library.json")
        return try ExerciseLibrary(data: Data(contentsOf: url))
    }

    private func catalogURL() throws -> URL {
        try repository().appendingPathComponent("\(ExerciseLibraryText.table).xcstrings")
    }

    private func entries() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: catalogURL())
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(catalog["sourceLanguage"] as? String, "en")
        return try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
    }

    private func translation(_ entry: [String: Any]?, _ language: String) -> String? {
        let unit = ((entry?["localizations"] as? [String: Any])?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        guard unit?["state"] as? String == "translated", let value = unit?["value"] as? String,
              !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    /// The catalog compiled into a folder of `.lproj`s, as Xcode builds it.
    private func compiledCatalog() throws -> Bundle {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rytivo-library-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: output) }
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = ["xcstringstool", "compile", try catalogURL().path, "--output-directory", output.path]
        try compile.run()
        compile.waitUntilExit()
        XCTAssertEqual(compile.terminationStatus, 0, "xcstringstool could not compile the library catalog")
        return try XCTUnwrap(Bundle(path: output.path))
    }

    private func bundle(_ language: String, in compiled: Bundle) throws -> Bundle {
        let path = try XCTUnwrap(compiled.path(forResource: language, ofType: "lproj"), "no \(language).lproj")
        return try XCTUnwrap(Bundle(path: path))
    }

    // MARK: - Coverage

    func testEveryNameAndStepIsTranslatedIntoEveryLanguage() throws {
        let library = try shippedLibrary()
        let entries = try entries()
        let texts = Set(library.exercises.flatMap { [$0.name] + $0.instructions })
        for language in Self.translatedLanguages {
            let missing = texts.filter { translation(entries[$0], language) == nil }.sorted()
            XCTAssertTrue(missing.isEmpty, "\(missing.count) library texts have no \(language) translation: \(missing.prefix(5))")
        }
        // Nothing left over from a library that has since changed.
        let stale = Set(entries.keys).subtracting(texts).sorted()
        XCTAssertTrue(stale.isEmpty, "catalog entries the library no longer has: \(stale.prefix(5))")
    }

    func testNoEntryAsksForAGeneratedSymbol() throws {
        // The build generates a Swift symbol for every manual string unless
        // told not to, and two steps that differ only by a comma ("After a
        // brief pause, return…") map to the same symbol and fail the build.
        // Library text is looked up by its English, so none needs one.
        let asking = try entries().filter { $0.value["generatesSymbol"] as? Bool != false }.map(\.key)
        XCTAssertTrue(asking.isEmpty, "entries without \"generatesSymbol\": false: \(asking.prefix(5))")
    }

    func testEachLanguageIsWrittenInItsOwnScript() throws {
        // A pass that copied the English through would pass the check above.
        let scripts: [String: ClosedRange<UnicodeScalar>] = [
            "ar": "\u{0600}"..."\u{06FF}", "hi": "\u{0900}"..."\u{097F}",
            "ru": "\u{0400}"..."\u{04FF}", "ja": "\u{3040}"..."\u{30FF}",
            "zh-Hans": "\u{4E00}"..."\u{9FFF}",
        ]
        let entries = try entries()
        for (language, range) in scripts {
            let written = entries.values.filter { entry in
                translation(entry, language)?.unicodeScalars.contains { range.contains($0) } ?? false
            }
            XCTAssertGreaterThan(Double(written.count), Double(entries.count) * 0.97,
                                 "\(language) library translations are not in their script")
        }
    }

    func testNoTwoExercisesShareATranslatedName() throws {
        // Both would sit in the same list with nothing to tell them apart.
        let library = try shippedLibrary()
        let entries = try entries()
        for language in Self.translatedLanguages {
            var seen: [String: String] = [:]
            for exercise in library.exercises {
                guard let name = translation(entries[exercise.name], language) else { continue }
                let key = name.lowercased()
                if let other = seen[key] {
                    XCTFail("\(language): “\(name)” is both \(other) and \(exercise.name)")
                }
                seen[key] = exercise.name
            }
        }
    }

    func testTheEquipmentStaysInBrackets() throws {
        // "Bench Press (Dumbbell)": the bracket is how a list tells the
        // versions of one movement apart.
        let library = try shippedLibrary()
        let entries = try entries()
        for exercise in library.exercises where exercise.name.contains("(") {
            for language in Self.translatedLanguages {
                let name = translation(entries[exercise.name], language) ?? ""
                XCTAssertTrue(name.contains("(") || name.contains("（"), "\(language) “\(exercise.name)” is “\(name)”")
            }
        }
    }

    // MARK: - At runtime

    func testNamesAndStepsAreFoundInTheChosenLanguage() throws {
        let library = try shippedLibrary()
        let compiled = try compiledCatalog()
        let entries = try entries()
        let sample = try XCTUnwrap(library.exercises.first { $0.instructions.count > 1 })
        for language in AppLanguage.allCases.map(\.rawValue) {
            let bundle = try bundle(language, in: compiled)
            let name = ExerciseLibraryText.localized(sample.name, in: bundle)
            let step = ExerciseLibraryText.localized(sample.instructions[1], in: bundle)
            if language == "en" {
                XCTAssertEqual(name, sample.name)
            } else {
                XCTAssertEqual(name, translation(entries[sample.name], language), language)
                XCTAssertEqual(step, translation(entries[sample.instructions[1]], language), language)
                XCTAssertNotEqual(step, sample.instructions[1], "\(language) shows the English step")
            }
        }
    }

    func testATextTheCatalogLacksReadsInEnglish() throws {
        let bundle = try bundle("ja", in: compiledCatalog())
        XCTAssertEqual(ExerciseLibraryText.localized("Zero Gravity Lunge (Hoverboard)", in: bundle),
                       "Zero Gravity Lunge (Hoverboard)", "an exercise added since the last translation")
    }

    func testOnlyTheLibrarysOwnNamesAreTranslated() throws {
        let library = try shippedLibrary()
        let spanish = try bundle("es", in: compiledCatalog())
        let exercise = try XCTUnwrap(library.exercises.first { exercise in
            !exercise.aliases.isEmpty && library.exercises.allSatisfy { ExerciseSearch.folded($0.name) != ExerciseSearch.folded(exercise.aliases[0]) }
        })
        let translated = library.displayName(for: exercise.name, in: spanish)
        XCTAssertNotEqual(translated, exercise.name, "the library's name is shown in Spanish")
        XCTAssertEqual(library.displayName(for: exercise.name.uppercased(), in: spanish), translated,
                       "however the server cased it")
        XCTAssertEqual(library.displayName(for: exercise.aliases[0], in: spanish), exercise.aliases[0],
                       "a name somebody chose that only matches an alias is theirs")
        XCTAssertEqual(library.displayName(for: "Grandma's Garden Squats", in: spanish), "Grandma's Garden Squats",
                       "somebody's own exercise keeps its name")
    }

    func testSearchFindsAnExerciseByItsNameInEitherLanguage() throws {
        let library = try shippedLibrary()
        let compiled = try compiledCatalog()
        let entries = try entries()
        let bench = try XCTUnwrap(library.exercise(named: "Bench Press (Barbell)") ?? library.exercises.first)
        for language in Self.translatedLanguages {
            let bundle = try bundle(language, in: compiled)
            let shown = try XCTUnwrap(translation(entries[bench.name], language))
            XCTAssertEqual(library.search(shown, in: bundle).first?.slug, bench.slug, "\(language): \(shown)")
            XCTAssertEqual(library.search(bench.name, in: bundle).first?.slug, bench.slug,
                           "\(language): the English name still finds it")
        }
    }

    func testAnEmptySearchListsNamesInTheLanguagesOwnOrder() throws {
        let library = try shippedLibrary()
        let spanish = try bundle("es", in: compiledCatalog())
        let shown = library.search("", in: spanish).prefix(40).map { ExerciseLibraryText.localized($0.name, in: spanish) }
        let sorted = shown.sorted {
            $0.compare($1, options: [.caseInsensitive, .numeric], range: nil, locale: Locale(identifier: "es")) == .orderedAscending
        }
        XCTAssertEqual(shown, sorted)
    }

    func testSwitchingLanguageChangesExerciseNamesWithoutRelaunching() throws {
        let library = try shippedLibrary()
        let compiled = try compiledCatalog()
        let suite = "rytivo.library.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let localization = AppLocalization(
            settings: AppLanguageSettings(defaults: defaults, domainName: suite),
            resources: compiled
        )
        let name = try XCTUnwrap(library.exercises.first?.name)
        var seen: [AppLanguage: String] = [:]
        for language in AppLanguage.allCases {
            localization.select(.language(language))
            seen[language] = library.displayName(for: name, in: localization.bundle)
        }
        XCTAssertEqual(seen[.english], name)
        // Two languages may agree (Spanish and Portuguese both say "Abdominal
        // 3/4"); what matters is that none is left in English.
        for language in AppLanguage.allCases where language != .english {
            XCTAssertNotEqual(seen[language], name, "\(language) still shows English")
        }
    }
}
