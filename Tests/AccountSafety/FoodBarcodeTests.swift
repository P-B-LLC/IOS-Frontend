import Foundation
import XCTest
@testable import AccountSafety

final class FoodBarcodeTests: XCTestCase {
    func testLeadingZeroAndChecksum() {
        XCTAssertEqual(FoodBarcode.validated("034000470693"), "0034000470693")
        XCTAssertEqual(FoodBarcode.validated("3017620422003"), "3017620422003")
        XCTAssertEqual(FoodBarcode.validated("96385074"), "96385074")
        for input in ["3017620422004", "123", "https://example.com", "１２３４５６７８", "../3017620422003"] {
            XCTAssertNil(FoodBarcode.validated(input))
        }
    }
    func testBarcodeTypedInNativeDigits() {
        XCTAssertEqual(FoodBarcode.validated("٣٠١٧٦٢٠٤٢٢٠٠٣"), "3017620422003")
        XCTAssertNil(FoodBarcode.validated("٣٠١٧٦٢٠٤٢٢٠٠٤"))
    }
    func testUPCEExpandsBeforeGTINValidation() {
        XCTAssertEqual(FoodBarcode.expandUPCE("04252614"), FoodBarcode.validated("042100005264"))
        XCTAssertNotNil(FoodBarcode.expandUPCE("04252614"))
        XCTAssertNil(FoodBarcode.expandUPCE("04252615"))
    }
    func testSearchRequiresSubmissionAndScannerNeverSavesDirectly() throws {
        let root = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"]))
        let picker = try String(contentsOf: root.appendingPathComponent("IOS Frontend/IOS Frontend/Views/Food/FoodPickerView.swift"), encoding: .utf8)
        XCTAssertFalse(picker.contains(".task(id: searchText)"))
        XCTAssertTrue(picker.contains(".task(id: searchRevision)"))
        XCTAssertTrue(picker.contains("query == submittedQuery"))
        XCTAssertTrue(picker.contains("product.servingDescription"))
        let scanner = try String(contentsOf: root.appendingPathComponent("IOS Frontend/IOS Frontend/Views/Food/FoodBarcodeSheet.swift"), encoding: .utf8)
        XCTAssertFalse(scanner.contains("saveFood"))
        XCTAssertFalse(scanner.contains("URLSession"))
        XCTAssertTrue(scanner.contains("stopScanning()"))
    }

    func testSearchLifecycleDiscardsOldCredentialsAndFailures() throws {
        let root = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"]))
        let source = try String(contentsOf: root.appendingPathComponent("IOS Frontend/IOS Frontend/Stores/FoodTrackingStore.swift"), encoding: .utf8)
        let connect = try XCTUnwrap(source.components(separatedBy: "func connect(configuration:").last?
            .components(separatedBy: "func disconnect()").first)
        XCTAssertEqual(connect.components(separatedBy: "catalogue = nil").count - 1, 2,
                       "Connecting resets an old credential client; failed connection clears its new client")
        let disconnect = try XCTUnwrap(source.components(separatedBy: "func disconnect()").last?
            .components(separatedBy: "func reset()").first)
        XCTAssertTrue(disconnect.contains("catalogue = nil"))
        let search = try XCTUnwrap(source.components(separatedBy: "func searchCatalogue(").last?
            .components(separatedBy: "func catalogueDetails(").first)
        XCTAssertTrue(search.contains("guard isConnected, let catalogue"))
        XCTAssertTrue(search.contains("} catch {"))
        XCTAssertEqual(search.components(separatedBy: "guard generation == connectionGeneration, !Task.isCancelled").count - 1, 2,
                       "Both successful responses and failures must belong to the current account")
    }

    func testRepeatedSubmissionDoesNotRestartAnIdenticalInFlightSearch() throws {
        let root = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"]))
        let picker = try String(contentsOf: root.appendingPathComponent("IOS Frontend/IOS Frontend/Views/Food/FoodPickerView.swift"), encoding: .utf8)
        let submit = try XCTUnwrap(picker.components(separatedBy: "private func submitSearch()").last?
            .components(separatedBy: "private func searchDatabase()").first)
        XCTAssertTrue(submit.contains("guard !isSaving, query.count >= 2"))
        XCTAssertTrue(submit.contains("!(isSearchingDatabase && submittedQuery == query)"))
        XCTAssertTrue(submit.contains("submittedQuery = query"))
    }
}
