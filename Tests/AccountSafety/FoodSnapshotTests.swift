import Foundation
import HTTPTypes
import OpenAPIRuntime
import RepbaseAPI
import XCTest
@testable import AccountSafety

private actor FoodSnapshotTransport: ClientTransport {
    struct Reply: Sendable { let status: Int; let json: String }
    struct Sent: Sendable { let path: String?; let operation: String; let key: String?; let body: Data }
    private var replies: [Reply]
    private(set) var sent: [Sent] = []
    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let data: Data
        if let body { data = try await Data(collecting: body, upTo: 1_048_576) }
        else { data = Data() }
        sent.append(Sent(path: request.path, operation: operationID,
                         key: request.headerFields[.init("Idempotency-Key")!], body: data))
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let reply = replies.removeFirst()
        var response = HTTPResponse(status: .init(code: reply.status))
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(Data(reply.json.utf8)))
    }
}

final class FoodSnapshotTests: XCTestCase {
    private let origin = URL(string: "https://snapshot-tests.invalid")!
    private let nutrients: [String: Decimal] = ["fiber_g": 0, "calcium_mg": Decimal(string: "123.456789")!, "vitamin_d_ug": Decimal(string: "0.000001")!]
    private let macro = NutritionAmount(calories: 25.55, proteinGrams: 1.11, carbohydrateGrams: 4.44, fatGrams: 0.33)

    private func food() -> FoodEntry {
        FoodEntry(serverID: 8, name: "Spread", servings: Decimal(string: "10.428571")!, nutritionPerServing: macro,
                  sourceID: "off:3017620422003", servingDescription: "1 tsp (7 g)",
                  referenceQuantity: 7, referenceUnit: "g", nutrients: nutrients)
    }

    private func fixture(servings: String = "10.428571", includeMetadata: Bool = true) throws -> String {
        var object: [String: Any] = [
            "id": 8, "meal": 7, "name": "Spread", "brand": "", "servings": servings,
            "calories": "25.55", "protein_grams": "1.11", "carbohydrate_grams": "4.44", "fat_grams": "0.33",
            "total_calories": "266.45", "total_protein_grams": "11.58", "total_carbohydrate_grams": "46.30", "total_fat_grams": "3.44",
            "created_at": "2026-11-02T12:00:00Z", "updated_at": "2026-11-02T12:00:00Z"
        ]
        if includeMetadata {
            object.merge([
                "source_id": "off:3017620422003", "serving_description": "1 tsp (7 g)",
                "reference_quantity": "7.0000", "reference_unit": "g",
                "nutrients": ["fiber_g": "0.000000", "calcium_mg": "123.456789", "vitamin_d_ug": "0.000001"]
            ]) { _, value in value }
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func repository(_ transport: FoodSnapshotTransport) -> FoodAPIRepository {
        FoodAPIRepository(configuration: APIConfiguration(serverURL: origin, allowsInsecureLocalhost: false),
                          client: Client(serverURL: origin, transport: transport))
    }

    func testHistoricalRecoveryWithoutMetadataStillDecodesWithItsIdentity() throws {
        let id = UUID()
        let old = #"{"id":"\#(id)","serverID":8,"name":"Old food","servings":1.5,"nutritionPerServing":{"calories":20.25,"proteinGrams":1,"carbohydrateGrams":2,"fatGrams":3}}"#
        let decoded = try JSONDecoder().decode(FoodEntry.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.serverID, 8)
        XCTAssertEqual(decoded.servings, Decimal(string: "1.5"))
        XCTAssertEqual(decoded.nutritionPerServing.calories, Decimal(string: "20.25"))
        XCTAssertNil(decoded.referenceQuantity)
        XCTAssertNil(decoded.referenceUnit)
        XCTAssertNil(decoded.sourceID)
        XCTAssertTrue(decoded.nutrients.isEmpty, "Unknown historical values are not zero-filled")
        XCTAssertEqual(decoded.snapshotVersion, 1)
    }

    func testNewRecoveryRoundTripPreservesReferenceAndKnownZero() throws {
        let original = food()
        let decoded = try JSONDecoder().decode(FoodEntry.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.nutrients["fiber_g"], 0)
        XCTAssertNil(decoded.nutrients["iron_mg"])
    }

    func testCopyForLoggingCreatesNewIdentityButKeepsCompleteSnapshot() {
        let original = food()
        let copy = original.copyForLogging()
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertNil(copy.serverID)
        XCTAssertEqual(original.serverID, 8)
        XCTAssertEqual(copy.referenceQuantity, 7)
        XCTAssertEqual(copy.referenceUnit, "g")
        XCTAssertEqual(copy.servingDescription, original.servingDescription)
        XCTAssertEqual(copy.sourceID, original.sourceID)
        XCTAssertEqual(copy.nutrients, original.nutrients)
        XCTAssertEqual(copy.nutritionPerServing, original.nutritionPerServing)
        XCTAssertEqual(copy.snapshotVersion, 2)
    }

    func testNutrientMultiplierNeverManufacturesMissingValues() {
        var entry = food()
        entry.servings = Decimal(string: "0.5")!
        XCTAssertEqual(entry.totalNutrients["calcium_mg"], Decimal(string: "61.7283945"))
        XCTAssertEqual(entry.totalNutrients["fiber_g"], 0)
        XCTAssertNil(entry.totalNutrients["iron_mg"])
    }

    func testManualQuantityAndNameEditRetainReferenceButMacroEditClearsIt() {
        let original = food()
        var quantityOnly = FoodEntry(name: "Renamed", servings: 2, nutritionPerServing: macro)
        quantityOnly.preserveSourceDetails(ifNutritionMatches: original)
        XCTAssertEqual(quantityOnly.nutrients, nutrients)
        XCTAssertEqual(quantityOnly.referenceQuantity, 7)
        XCTAssertEqual(quantityOnly.sourceID, original.sourceID)
        quantityOnly.nutritionPerServing.calories += 1
        quantityOnly.preserveSourceDetails(ifNutritionMatches: original)
        XCTAssertTrue(quantityOnly.nutrients.isEmpty)
        XCTAssertNil(quantityOnly.sourceID)
        XCTAssertNil(quantityOnly.servingDescription)
        XCTAssertNil(quantityOnly.referenceQuantity)
        XCTAssertNil(quantityOnly.referenceUnit)
    }

    func testSnapshotMapperRejectsInvalidNumbersAndUnpairedOrUnknownUnits() {
        let base = FoodEntry(name: "Food", nutritionPerServing: macro)
        let mapped = FoodSnapshotPolicy.attaching(to: base, sourceID: nil, servingDescription: "Label",
            referenceQuantity: "20", referenceUnit: "serving",
            nutrients: ["fiber_g": "0", "calcium_mg": "NaN", "iron_mg": "1oops", "unknown": "2"])
        XCTAssertNil(mapped.referenceQuantity)
        XCTAssertNil(mapped.referenceUnit)
        XCTAssertEqual(mapped.nutrients, ["fiber_g": 0])
        let liquid = FoodSnapshotPolicy.attaching(to: base, sourceID: nil, servingDescription: "100 ml",
            referenceQuantity: "100", referenceUnit: "ml", nutrients: [:])
        XCTAssertEqual(liquid.referenceUnit, "ml", "A liquid reference never becomes a gram reference")
    }

    func testDiaryCreateUsesSixDigitMultiplierAndPreservesMetadataInActualTransport() async throws {
        let transport = FoodSnapshotTransport([.init(status: 201, json: try fixture())])
        let saved = try await repository(transport).saveFood(food().copyForLogging(), inMeal: 7)
        XCTAssertEqual(saved.nutrients, nutrients)
        XCTAssertEqual(saved.referenceQuantity, 7)
        XCTAssertEqual(saved.sourceID, "off:3017620422003")
        let sent = await transport.sent
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.first).body) as? [String: Any])
        XCTAssertEqual(body["servings"] as? String, "10.428571")
        XCTAssertEqual(body["reference_quantity"] as? String, "7")
        XCTAssertEqual(body["reference_unit"] as? String, "g")
        let values = try XCTUnwrap(body["nutrients"] as? [String: String])
        XCTAssertEqual(values["vitamin_d_ug"], "0.000001")
        XCTAssertEqual(values["calcium_mg"], "123.456789")
        XCTAssertEqual(values["fiber_g"], "0")
    }

    func testUnknownMetadataIsOmittedFromCreateSoOldRetryFingerprintDoesNotChange() async throws {
        let transport = FoodSnapshotTransport([.init(status: 201, json: try fixture(includeMetadata: false))])
        _ = try await repository(transport).saveFood(FoodEntry(name: "Manual", nutritionPerServing: macro), inMeal: 7)
        let sent = await transport.sent
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.first).body) as? [String: Any])
        for key in ["source_id", "serving_description", "reference_quantity", "reference_unit", "nutrients"] {
            XCTAssertNil(body[key], key)
        }
    }

    func testLegacyCapturedCreateKeepsItsOriginalTwoDecimalMultiplier() async throws {
        let id = UUID()
        let old = #"{"id":"\#(id)","name":"Old food","servings":1.234567,"nutritionPerServing":{"calories":20.25,"proteinGrams":1,"carbohydrateGrams":2,"fatGrams":3}}"#
        let captured = try JSONDecoder().decode(FoodEntry.self, from: Data(old.utf8))
        let transport = FoodSnapshotTransport([.init(status: 201, json: try fixture(servings: "1.23", includeMetadata: false))])
        _ = try await repository(transport).saveFood(captured, inMeal: 7)
        let sent = await transport.sent
        XCTAssertEqual(sent.count, 1)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.first).body) as? [String: Any])
        let expected: [String: Any] = ["meal": 7, "name": "Old food", "servings": "1.23", "calories": "20.25",
                                       "protein_grams": "1", "carbohydrate_grams": "2", "fat_grams": "3"]
        XCTAssertEqual(body as NSDictionary, expected as NSDictionary,
                       "Every original member/value must match, with no new empty metadata or local recovery-version field")
        XCTAssertEqual(sent.first?.key, id.uuidString)
        XCTAssertEqual(captured.copyForLogging().snapshotVersion, 2, "A genuinely new log may use six-digit precision")
    }

    func testManualMacroEditPatchExplicitlyClearsOldSourceAndNutrients() async throws {
        let transport = FoodSnapshotTransport([.init(status: 200, json: try fixture(includeMetadata: false))])
        let original = food()
        var revised = original
        revised.nutritionPerServing.calories += 1
        revised.preserveSourceDetails(ifNutritionMatches: original)
        _ = try await repository(transport).saveFood(revised, inMeal: 7)
        let sent = await transport.sent
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.first).body) as? [String: Any])
        XCTAssertEqual(body["source_id"] as? String, "")
        XCTAssertEqual(body["serving_description"] as? String, "")
        XCTAssertEqual(body["reference_unit"] as? String, "")
        XCTAssertTrue(try XCTUnwrap(body["nutrients"] as? [String: String]).isEmpty)
    }

    func testSelectedCatalogueDetailSuppliesReferenceAndNutrients() async throws {
        let transport = FoodSnapshotTransport([.init(status: 200, json: "[" + (try fixture()) + "]")])
        let catalogue = FoodDatabaseRepository(client: Client(serverURL: origin, transport: transport))
        let detail = try await catalogue.details(for: FoodCatalogueCandidate(sourceID: "off:3017620422003", name: "Spread", brand: ""))
        let entry = try XCTUnwrap(detail).entry
        XCTAssertEqual(entry.referenceQuantity, 7)
        XCTAssertEqual(entry.referenceUnit, "g")
        XCTAssertEqual(entry.servingDescription, "1 tsp (7 g)")
        XCTAssertEqual(entry.nutrients, nutrients)
    }

    func testOldBackendDiaryReadKeepsMissingMetadataUnknown() async throws {
        let transport = FoodSnapshotTransport([.init(status: 200, json: "[" + (try fixture(includeMetadata: false)) + "]")])
        let recent = try await repository(transport).recentFoods()
        XCTAssertNil(recent.first?.referenceQuantity)
        XCTAssertTrue(try XCTUnwrap(recent.first).nutrients.isEmpty)
        XCTAssertEqual(recent.first?.nutritionPerServing.calories, Decimal(string: "25.55"))
    }

    func testRecentReadRetainsKnownServingWeightAndNutrients() async throws {
        let transport = FoodSnapshotTransport([.init(status: 200, json: "[" + (try fixture()) + "]")])
        let recent = try await repository(transport).recentFoods()
        let entry = try XCTUnwrap(recent.first)
        XCTAssertEqual(entry.referenceQuantity, 7)
        XCTAssertEqual(entry.referenceUnit, "g")
        XCTAssertEqual(entry.servingDescription, "1 tsp (7 g)")
        XCTAssertEqual(entry.nutrients, nutrients)
    }

    func testRecipeWritePreservesIngredientReferenceAndNutrients() async throws {
        let ingredient = try JSONSerialization.jsonObject(with: Data(fixture().utf8))
        let object: [String: Any] = ["id": 5, "name": "Recipe", "ingredients": [ingredient], "cookbook": 1,
                                   "created_at": "2026-11-02T12:00:00Z", "updated_at": "2026-11-02T12:00:00Z"]
        let response = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let transport = FoodSnapshotTransport([.init(status: 201, json: response)])
        let recipe = SavedFoodMeal(name: "Recipe", ingredients: [food()], cookbookID: 1)
        let saved = try await repository(transport).saveRecipe(recipe)
        XCTAssertEqual(saved.ingredients.first?.referenceQuantity, 7)
        XCTAssertEqual(saved.ingredients.first?.nutrients, nutrients)
        let sent = await transport.sent
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.first).body) as? [String: Any])
        let ingredients = try XCTUnwrap(body["ingredients"] as? [[String: Any]])
        XCTAssertEqual(ingredients.first?["servings"] as? String, "10.428571")
        XCTAssertEqual(ingredients.first?["reference_unit"] as? String, "g")
        XCTAssertEqual((ingredients.first?["nutrients"] as? [String: String])?["fiber_g"], "0")
    }
}
