import Foundation
import XCTest
@testable import AccountSafety

/// The bottom bar draws icons only, so each tab's title is now what VoiceOver
/// reads and nothing else says it. A title missing from a language would be
/// heard in English, or as the raw key; an icon name that names no asset
/// would draw nothing at all.
final class IconOnlyTabBarTests: XCTestCase {
    private var root: URL {
        get throws {
            let path = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
            return URL(fileURLWithPath: path).appendingPathComponent("IOS Frontend/IOS Frontend")
        }
    }

    /// The catalog key each tab title is looked up by.
    private func key(for tab: RepbaseTab) -> String {
        switch tab {
        case .home: "tab.home"
        case .training: "Training"
        case .planner: "Calendar"
        case .social: "Social"
        case .account: "Account"
        }
    }

    private func catalog() throws -> [String: Any] {
        let data = try Data(contentsOf: try root.appendingPathComponent("Localizable.xcstrings"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["strings"] as? [String: Any])
    }

    func testEveryTabHasASpokenTitle() {
        for tab in RepbaseTab.allCases {
            XCTAssertFalse(tab.title.trimmingCharacters(in: .whitespaces).isEmpty, tab.rawValue)
        }
        // The one key that is not English text must never be read out as is.
        XCTAssertNotEqual(RepbaseTab.home.title, "tab.home")
        for tab in RepbaseTab.allCases {
            XCTAssertFalse(tab.title.hasPrefix("tab."), tab.rawValue)
        }
    }

    func testEveryTabTitleIsTranslatedInEveryAppLanguage() throws {
        let strings = try catalog()
        for tab in RepbaseTab.allCases {
            let entry = try XCTUnwrap(strings[key(for: tab)] as? [String: Any], "\(key(for: tab)) is not in the catalog")
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in AppLanguage.allCases where language != .english {
                let unit = (localizations[language.rawValue] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(tab.rawValue) has no \(language.rawValue) title")
                XCTAssertEqual(unit?["state"] as? String, "translated", "\(tab.rawValue) in \(language.rawValue)")
            }
        }
    }

    func testTheHomeTabIsNotTheHouseholdCategoryWord() throws {
        // "Home" the tab and "Home" the planner category are different words in
        // most languages, so the tab has its own key with an English default.
        let strings = try catalog()
        XCTAssertNotNil(strings["tab.home"])
        XCTAssertEqual(key(for: .home), "tab.home")
    }

    func testEveryTabIconNamesAnAssetThatExists() throws {
        let assets = try root.appendingPathComponent("Assets.xcassets")
        for tab in RepbaseTab.allCases {
            let set = assets.appendingPathComponent("\(tab.iconAsset).imageset/Contents.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: set.path), "\(tab.iconAsset) is missing")
        }
    }

    func testIconNamesAndIdentifiersAreDistinct() {
        let icons = RepbaseTab.allCases.map(\.iconAsset)
        XCTAssertEqual(Set(icons).count, icons.count)
        let ids = RepbaseTab.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testTheBarLabelsEachButtonWithItsTitleAndAStableIdentifier() throws {
        let source = try String(contentsOf: try root.appendingPathComponent("Views/Navigation/RepbaseRootView.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains(".accessibilityLabel(item.title)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"tab.\\(item.rawValue)\")"))
    }
}
