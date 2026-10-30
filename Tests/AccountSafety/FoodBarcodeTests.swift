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
        XCTAssertTrue(picker.contains("result.servingDescription"))
        let scanner = try String(contentsOf: root.appendingPathComponent("IOS Frontend/IOS Frontend/Views/Food/FoodBarcodeSheet.swift"), encoding: .utf8)
        XCTAssertFalse(scanner.contains("saveFood"))
        XCTAssertFalse(scanner.contains("URLSession"))
        XCTAssertTrue(scanner.contains("stopScanning()"))
    }
}
