import Foundation
import HTTPTypes
import OpenAPIRuntime
import RepbaseAPI
import XCTest
@testable import AccountSafety

private actor FoodCatalogueTransport: ClientTransport {
    struct Reply: Sendable {
        var status = 200
        let json: String
        var retryAfter: String? = nil
    }
    struct Request: Sendable {
        let path: String?
        let operation: String
    }
    private var replies: [Reply]
    private(set) var requests: [Request] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        requests.append(Request(path: request.path, operation: operationID))
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let reply = replies.removeFirst()
        var response = HTTPResponse(status: .init(code: reply.status))
        response.headerFields[.contentType] = "application/json"
        response.headerFields[.init("Retry-After")!] = reply.retryAfter
        return (response, HTTPBody(Data(reply.json.utf8)))
    }
}

final class FoodCatalogueTests: XCTestCase {
    private let sourceID = "off:3017620422003"
    private let candidates = #"[{"source_id":"off:3017620422003","name":"Rice drink","brand":"Example"}]"#
    private let complete = #"[{"source_id":"off:3017620422003","name":"Rice drink","brand":"Example","serving_description":"100 ml","calories":"45.50","protein_grams":"1.20","carbohydrate_grams":"7.25","fat_grams":"0.50"}]"#

    private func repository(_ transport: FoodCatalogueTransport) -> FoodDatabaseRepository {
        FoodDatabaseRepository(client: Client(serverURL: URL(string: "https://food-tests.invalid")!, transport: transport))
    }

    func testTextSearchReturnsIdentitiesWithoutInventingNutritionOrServing() async throws {
        let transport = FoodCatalogueTransport([.init(json: candidates)])
        let rows = try await repository(transport).search(" rice ")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.sourceID, sourceID)
        XCTAssertEqual(row.title, "Rice drink · Example")
        XCTAssertNil(row.verifiedResult)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.operation), ["food_discover_list"])
        XCTAssertTrue(try XCTUnwrap(requests.first?.path).contains("q=rice"))
    }

    func testChoosingCandidateFetchesItsExactBarcodeAndPreservesLiquidBasis() async throws {
        let transport = FoodCatalogueTransport([.init(json: candidates), .init(json: complete)])
        let catalogue = repository(transport)
        let rows = try await catalogue.search("rice")
        let candidate = try XCTUnwrap(rows.first)
        let detail = try await catalogue.details(for: candidate)
        let product = try XCTUnwrap(detail)
        XCTAssertEqual(product.sourceID, sourceID)
        XCTAssertEqual(product.servingDescription, "100 ml", "Never turn an index result into an assumed 100 g serving")
        XCTAssertEqual(product.entry.nutritionPerServing.calories, Decimal(string: "45.50"))
        XCTAssertEqual(product.entry.nutritionPerServing.carbohydrateGrams, Decimal(string: "7.25"))
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.operation), ["food_discover_list", "food_search_list"])
        XCTAssertTrue(try XCTUnwrap(requests.last?.path).contains("3017620422003"))
    }

    func testBarcodeSearchRemainsCompleteAndDoesNotCallDiscoveryOrRefetchOnSelection() async throws {
        let transport = FoodCatalogueTransport([.init(json: complete)])
        let catalogue = repository(transport)
        let rows = try await catalogue.search("barcode:3017620422003")
        let candidate = try XCTUnwrap(rows.first)
        XCTAssertNotNil(candidate.verifiedResult)
        let detail = try await catalogue.details(for: candidate)
        XCTAssertEqual(detail?.servingDescription, "100 ml")
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.operation), ["food_search_list"])
    }

    func testTypedBarcodeUsesDetailRatherThanTextIndex() async throws {
        let transport = FoodCatalogueTransport([.init(json: complete)])
        _ = try await repository(transport).search("3017620422003")
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.operation), ["food_search_list"])
    }

    func testScannedBarcodeNeverAcceptsAnotherReturnedProduct() async throws {
        let transport = FoodCatalogueTransport([.init(json: complete.replacingOccurrences(of: sourceID, with: "off:0034000470693"))])
        let rows = try await repository(transport).search("barcode:3017620422003")
        XCTAssertTrue(rows.isEmpty)
    }

    func testOldBackend404FallsBackOnlyToCompleteLegacyResults() async throws {
        let transport = FoodCatalogueTransport([.init(status: 404, json: "{}"), .init(json: complete)])
        let rows = try await repository(transport).search("rice")
        XCTAssertEqual(rows.first?.verifiedResult?.entry.nutritionPerServing.calories, Decimal(string: "45.50"))
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.operation), ["food_discover_list", "food_search_list"])
    }

    func testAuthThrottlesAndOutagesNeverIssueLegacyFallback() async throws {
        for status in [401, 403, 429, 500, 503] {
            let transport = FoodCatalogueTransport([.init(status: status, json: "{}")])
            do {
                _ = try await repository(transport).search("rice")
                XCTFail("Expected failure for \(status)")
            } catch {
                if status == 401 { XCTAssertEqual(error as? FoodCatalogueFailure, .sessionExpired) }
                else if status == 429 { XCTAssertEqual(error as? FoodCatalogueFailure, .busy) }
                else { XCTAssertEqual((error as? RepbaseAPIHTTPError)?.statusCode, status) }
            }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1, "A failed search must not spend another provider slot")
        }
    }

    func test503WithRetryAfterIsBusyButOrdinary503RemainsUnavailable() async throws {
        let transport = FoodCatalogueTransport([.init(status: 503, json: "{}", retryAfter: "15")])
        do {
            _ = try await repository(transport).search("rice")
            XCTFail("Expected provider capacity failure")
        } catch { XCTAssertEqual(error as? FoodCatalogueFailure, .busy) }
        XCTAssertNil(FoodCataloguePolicy.failure(statusCode: 503, retryAfter: nil))
        XCTAssertNil(FoodCataloguePolicy.failure(statusCode: 503, retryAfter: " "))
    }

    func testMissingDetailsAndWrongProductCannotBecomeLoggableFood() async throws {
        let candidate = FoodCatalogueCandidate(sourceID: sourceID, name: "Rice drink", brand: "Example")
        for json in ["[]", complete.replacingOccurrences(of: sourceID, with: "off:0034000470693")] {
            let transport = FoodCatalogueTransport([.init(json: json)])
            let detail = try await repository(transport).details(for: candidate)
            XCTAssertNil(detail)
        }
    }

    func testInvalidCandidateIDNeverCallsDetailEndpoint() async throws {
        for id in ["usda:12", "off:3017620422004", "off:../3017620422003", "off:034000470693"] {
            let transport = FoodCatalogueTransport([])
            let detail = try await repository(transport).details(for: .init(sourceID: id, name: "Rice", brand: ""))
            XCTAssertNil(detail)
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func testMalformedNutritionIsRejectedInsteadOfReplacedWithZeros() async throws {
        for malformed in ["not available", "NaN", "-1", "1abc", "1,20", "1\n"] {
            XCTAssertNil(FoodCataloguePolicy.nutrition(calories: malformed, protein: "1.2", carbs: "7.25", fat: "0.50"))
        }
        let transport = FoodCatalogueTransport([.init(json: complete.replacingOccurrences(of: "45.50", with: "unknown"))])
        let detail = try await repository(transport).details(for: .init(sourceID: sourceID, name: "Rice", brand: ""))
        XCTAssertNil(detail)
    }

    func testLongProductLabelRemainsDisplayableButDiarySnapshotFitsItsField() async throws {
        let title = String(repeating: "Rice drink ", count: 30)
        let candidate = FoodCatalogueCandidate(sourceID: sourceID, name: title, brand: "Example")
        XCTAssertGreaterThan(candidate.title.unicodeScalars.count, 150)
        XCTAssertLessThanOrEqual(FoodCataloguePolicy.diaryName(candidate.title).unicodeScalars.count, 150)
        let combined = String(repeating: "e\u{301}", count: 100)
        XCTAssertEqual(FoodCataloguePolicy.diaryName(combined).unicodeScalars.count, 150,
                       "The server limit counts code points, not Swift extended graphemes")
        let transport = FoodCatalogueTransport([.init(json: complete.replacingOccurrences(of: "Rice drink", with: title))])
        let detail = try await repository(transport).details(for: candidate)
        XCTAssertLessThanOrEqual(try XCTUnwrap(detail).entry.name.unicodeScalars.count, 150)
    }

    func testPreCancelledSearchDoesNotMakeAnyRequest() async throws {
        let transport = FoodCatalogueTransport([])
        let catalogue = repository(transport)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await catalogue.search("rice")
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
}
