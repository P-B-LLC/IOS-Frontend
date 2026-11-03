import Foundation
import XCTest
@testable import AccountSafety

/// Source checks protect the existing asynchronous wiring during a visual-only
/// change. Native simulator captures, not these checks, establish layout.
final class FoodPickerPresentationTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        return try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(relativePath),
                          encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n")
    }

    private func picker() throws -> String {
        try source("IOS Frontend/IOS Frontend/Views/Food/FoodPickerView.swift")
    }

    private func section(_ text: String, from start: String, to end: String) throws -> String {
        let beginning = try XCTUnwrap(text.range(of: start), "Missing source boundary: \(start)")
        let ending = try XCTUnwrap(text.range(of: end, range: beginning.upperBound..<text.endIndex),
                                  "Missing source boundary: \(end)")
        return String(text[beginning.lowerBound..<ending.lowerBound])
    }

    func testSearchStillRequiresExplicitSubmitAndFencesStaleResponses() throws {
        let view = try picker()
        XCTAssertTrue(view.contains(".onSubmit { submitSearch() }"))
        let submit = try section(view, from: "private func submitSearch()", to: "private func searchDatabase()")
        XCTAssertTrue(submit.contains("query.count >= 2"))
        XCTAssertTrue(submit.contains("isSearchingDatabase && submittedQuery == query"))
        let search = try section(view, from: "private func searchDatabase()", to: "private func chooseProduct(")
        XCTAssertTrue(search.contains("try await store.searchCatalogue(query)"))
        XCTAssertTrue(search.contains("revision == searchRevision, query == submittedQuery"))
        XCTAssertTrue(search.contains("!Task.isCancelled"))
        let change = try section(view, from: ".onChange(of: searchText)", to: ".sheet(isPresented: $showingBarcode")
        XCTAssertFalse(change.contains("store.searchCatalogue"))
        XCTAssertFalse(change.contains("submitSearch()"), "Typing must not spend a provider request")
    }

    func testSelectionStillHydratesExactCandidateAndRetainsRetryCancellation() throws {
        let view = try picker()
        let details = try section(view, from: "private func loadProductDetails()", to: "private func catalogueError(")
        XCTAssertTrue(details.contains("try await store.catalogueDetails(for: candidate)"))
        XCTAssertTrue(details.contains("revision == detailRevision"))
        XCTAssertTrue(details.contains("pendingCandidate?.id == candidate.id"))
        XCTAssertTrue(details.contains("selectedFood = product.entry"))
        XCTAssertTrue(view.contains("cancelProductDetails()"))
        XCTAssertTrue(view.contains("FoodPortionView(food: food"))
        XCTAssertTrue(view.contains("lockedForRetry: pendingAdd != nil, onAdd: add"))
    }

    func testSaveKeepsItsRecoveryIdentityAndSnapshotGuard() throws {
        let view = try picker()
        let add = try section(view, from: "private func add(_ food: FoodEntry)", to: "private func submitSearch()")
        XCTAssertTrue(add.contains("guard !isSaving else { return }"))
        XCTAssertTrue(add.contains("pendingAdd ?? food.copyForLogging()"))
        for field in ["nutritionPerServing", "sourceID", "referenceQuantity", "referenceUnit", "servingDescription", "nutrients"] {
            XCTAssertTrue(add.contains("pendingAdd.\(field) != food.\(field)"), "Lost retry snapshot field: \(field)")
        }
        XCTAssertTrue(add.contains("await store.saveFood("))
        XCTAssertTrue(view.contains("FoodPickerDraftRecovery(enabled: !isPreview, mealID: mealID"))
        XCTAssertTrue(view.contains("pendingAdd: $pendingAdd, saved: $draftSaved, error: $saveError"))
        XCTAssertTrue(view.contains(".interactiveDismissDisabled(isSaving)"))
        let recovery = try source("IOS Frontend/IOS Frontend/Views/Food/FoodPickerStyle.swift")
        XCTAssertTrue(recovery.contains("if enabled"))
        XCTAssertTrue(recovery.contains(".recoverableDraft(key: \"food-picker-\\(mealID)\""))
        XCTAssertTrue(recovery.contains("value: $pendingAdd"))
        XCTAssertTrue(recovery.contains("saved: $saved, error: $error"))
    }

    func testDebugPreviewReadAndWriteBranchesReturnBeforeProductionOperations() throws {
        let view = try picker()
        let boundaries = [
            ("private func add(_ food: FoodEntry)", "private func submitSearch()"),
            ("private func searchDatabase()", "private func chooseProduct("),
            ("private func loadProductDetails()", "private func catalogueError(")
        ]
        for (start, end) in boundaries {
            let operation = try section(view, from: start, to: end)
            let debug = try section(operation, from: "#if DEBUG", to: "#endif")
            XCTAssertTrue(debug.contains("previewScenario"))
            XCTAssertTrue(debug.contains("return"))
            XCTAssertFalse(debug.contains("store.searchCatalogue("))
            XCTAssertFalse(debug.contains("store.catalogueDetails("))
            XCTAssertFalse(debug.contains("store.saveFood("))
        }
        XCTAssertTrue(view.contains("FoodPickerPreviewFixtures.candidates"))
        XCTAssertTrue(view.contains("FoodPickerPreviewFixtures.detail(for: candidate)"))
    }

    func testOnlyHydratedRowsDisplayCaloriesAndTheReferenceBasis() throws {
        let view = try picker()
        let row = try section(view, from: "private struct DatabaseFoodRow", to: "private struct RecentFoodRow")
        XCTAssertTrue(row.contains("if let verified = result.verifiedResult"))
        XCTAssertTrue(row.contains("verified.servingDescription"))
        XCTAssertTrue(row.contains("verified.entry.totalNutrition.calories"))
        XCTAssertFalse(row.contains("?? 0"), "Unknown discovery calories are not zero")
    }

    func testNativePickerScenariosAndCaptureMatrixAreWired() throws {
        let app = try source("IOS Frontend/IOS Frontend/IOS_FrontendApp.swift")
        XCTAssertTrue(app.contains("scenario == \"picker\" || scenario.hasPrefix(\"picker-\")"))
        XCTAssertTrue(app.contains("FoodPickerView(date: Date(), mealID: meal.id, previewScenario: scenario)"))
        XCTAssertTrue(app.contains("scenario == \"picker-accessibility\" ? .accessibility3 : .large"))
        let capture = try source("Scripts/capture-cookbooks-preview.sh")
        XCTAssertTrue(capture.contains("-AppleLanguages '(en)'"))
        XCTAssertTrue(capture.contains("-AppleLanguages '(ar)'"))
        let workflow = try source(".github/workflows/ci.yml")
        for scenario in ["picker", "picker-results", "picker-error", "picker-loading", "picker-empty", "picker-accessibility"] {
            XCTAssertTrue(workflow.contains("\(scenario)-light"))
            XCTAssertTrue(workflow.contains("\(scenario)-dark"))
        }
        XCTAssertTrue(workflow.contains("picker-results-arabic-light"))
    }

    #if DEBUG
    func testPreviewDiscoveryContainsTruthfulKnownAndUnknownNutrition() throws {
        let candidates = FoodPickerPreviewFixtures.candidates
        let known = try XCTUnwrap(candidates.first { $0.verifiedResult != nil }?.verifiedResult)
        XCTAssertEqual(known.entry.referenceQuantity, Decimal(30))
        XCTAssertEqual(known.entry.referenceUnit, "g")
        XCTAssertEqual(known.entry.nutritionPerServing.calories, Decimal(111))
        XCTAssertTrue(candidates.contains { $0.verifiedResult == nil })
        for candidate in candidates {
            XCTAssertNotNil(FoodCataloguePolicy.barcode(sourceID: candidate.sourceID))
        }
    }

    func testPreviewDetailsHydrateAnIdentityWithoutNetworkAndLeaveIncompleteUnknown() throws {
        let candidates = FoodPickerPreviewFixtures.candidates
        let identity = try XCTUnwrap(candidates.first {
            $0.verifiedResult == nil && FoodPickerPreviewFixtures.detail(for: $0) != nil
        })
        let detail = try XCTUnwrap(FoodPickerPreviewFixtures.detail(for: identity))
        XCTAssertEqual(detail.sourceID, identity.sourceID)
        XCTAssertNil(identity.verifiedResult, "Details must not silently mutate the discovery row")
        XCTAssertTrue(candidates.contains {
            $0.verifiedResult == nil && FoodPickerPreviewFixtures.detail(for: $0) == nil
        })
        let fixture = try source("IOS Frontend/IOS Frontend/Views/Food/FoodPickerPreviewFixtures.swift")
        XCTAssertTrue(fixture.hasPrefix("#if DEBUG"))
        XCTAssertFalse(fixture.contains("URLSession"))
        XCTAssertFalse(fixture.contains("saveFood("))
    }

    func testPreviewZeroIsKnownAndLiquidReferenceDoesNotPretendToBeGrams() throws {
        let water = FoodPickerPreviewFixtures.zeroCalorieResult
        XCTAssertEqual(water.entry.nutritionPerServing.calories, Decimal.zero)
        XCTAssertEqual(water.entry.referenceQuantity, Decimal(100))
        XCTAssertEqual(water.entry.referenceUnit, "ml")
        let candidate = FoodCatalogueCandidate(verified: water)
        XCTAssertNotNil(candidate.verifiedResult)
        XCTAssertEqual(FoodPickerPreviewFixtures.detail(for: candidate)?.entry.nutritionPerServing, .zero)
    }
    #endif
}
