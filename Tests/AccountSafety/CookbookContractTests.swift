import Foundation
import HTTPTypes
import OpenAPIRuntime
import RepbaseAPI
import XCTest
@testable import AccountSafety

/// Answers every request with one canned response and keeps what was sent.
private actor CookbookTransport: ClientTransport {
    struct Sent: Sendable {
        let method: HTTPRequest.Method
        let path: String?
        let key: String?
        let body: Data
    }

    let status: Int
    let responseBody: String
    private(set) var sent: [Sent] = []

    init(status: Int = 200, responseBody: String = "{}") {
        self.status = status
        self.responseBody = responseBody
    }

    func send(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let data: Data
        if let body { data = try await Data(collecting: body, upTo: 1_048_576) }
        else { data = Data() }
        sent.append(.init(method: request.method, path: request.path,
                          key: request.headerFields[.init("Idempotency-Key")!], body: data))
        var response = HTTPResponse(status: .init(code: status))
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(Data(responseBody.utf8)))
    }
}

/// The cookbook calls the app makes, through the generated client, against
/// the shapes and refusals repbase actually sends.
final class CookbookContractTests: XCTestCase {
    private static let summary = #"{"id":4,"name":"Weeknight favorites","recipe_count":20,"capacity":20,"created_at":"2026-11-01T12:00:00Z","updated_at":"2026-11-01T12:00:00Z"}"#
    private static let savedRecipe = #"{"id":9,"name":"Curry","cookbook":5,"ingredients":[],"cooking_instructions":"Simmer.","created_at":"2026-11-01T12:00:00Z","updated_at":"2026-11-01T12:00:00Z"}"#

    private func client(_ transport: CookbookTransport) -> Client {
        Client(serverURL: URL(string: "https://test.invalid")!, transport: transport)
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Library

    func testCookbookSummaryCarriesCountAndCapacityButNoRecipes() async throws {
        let transport = CookbookTransport(
            responseBody: #"{"count":1,"next":null,"previous":null,"results":[\#(Self.summary)]}"#)
        guard case .ok(let response) = try await client(transport).foodCookbooksList(query: .init()) else {
            return XCTFail("A cookbook page is a documented 200")
        }
        let book = try XCTUnwrap(response.body.json.results.first)
        XCTAssertEqual(book.id, 4)
        XCTAssertEqual(book.recipeCount, 20)
        XCTAssertEqual(book.capacity, 20)
        let sent = await transport.sent
        XCTAssertEqual(sent.map(\.path), ["/api/v1/food/cookbooks/"])
        XCTAssertEqual(sent.first?.method, .get)
    }

    func testCreatingACookbookSendsItsNameUnderTheGivenSaveKey() async throws {
        let transport = CookbookTransport(status: 201, responseBody: Self.summary)
        let key = UUID()
        let output = try await client(transport).foodCookbooksCreate(
            headers: .init(idempotencyKey: key.uuidString), body: .json(.init(name: "Weeknight favorites")))
        guard case .created(let response) = output else { return XCTFail("Creation answers 201") }
        XCTAssertEqual(try response.body.json.name, "Weeknight favorites")
        let log = await transport.sent
        let sent = try XCTUnwrap(log.first)
        XCTAssertEqual(sent.method, .post)
        XCTAssertEqual(sent.key, key.uuidString, "A retried create must reuse its key, not make a second cookbook")
        XCTAssertEqual(try json(sent.body) as NSDictionary, ["name": "Weeknight favorites"])
    }

    func testOpeningOneCookbookAsksOnlyForItsRecipes() async throws {
        let transport = CookbookTransport(responseBody: #"{"count":0,"next":null,"previous":null,"results":[]}"#)
        _ = try await client(transport).foodSavedMealsList(query: .init(cookbook: 7, page: 2))
        let sent = await transport.sent
        let path = try XCTUnwrap(sent.first?.path)
        XCTAssertTrue(path.hasPrefix("/api/v1/food/saved-meals/?"), path)
        XCTAssertTrue(path.contains("cookbook=7"), path)
        XCTAssertTrue(path.contains("page=2"), path)
    }

    func testMovingARecipeSendsOnlyTheDestination() async throws {
        // A move must not resend the name or ingredients: those would be
        // validated again and could refuse a move that only changes the folder.
        let transport = CookbookTransport(responseBody: Self.savedRecipe)
        let output = try await client(transport).foodSavedMealsPartialUpdate(
            path: .init(id: 9), body: .json(.init(cookbook: 5)))
        guard case .ok(let response) = output else { return XCTFail("A move answers 200") }
        XCTAssertEqual(try response.body.json.cookbook, 5)
        let log = await transport.sent
        let sent = try XCTUnwrap(log.first)
        XCTAssertEqual(sent.method, .patch)
        XCTAssertEqual(sent.path, "/api/v1/food/saved-meals/9/")
        XCTAssertEqual(try json(sent.body) as NSDictionary, ["cookbook": 5])
    }

    // MARK: - Social

    func testSavingSomeonesMealSendsTheChosenCookbook() async throws {
        let transport = CookbookTransport(
            status: 201, responseBody: #"{"meal":12,"name":"Lunch","item_count":1,"renamed":false,"already_saved":false}"#)
        let output = try await client(transport).socialPostsSaveMealCreate(
            path: .init(id: 31), body: .json(.init(cookbook: 4)))
        guard case .created = output else { return XCTFail("A first save answers 201") }
        let log = await transport.sent
        let sent = try XCTUnwrap(log.first)
        XCTAssertEqual(sent.path, "/api/v1/social/posts/31/save-meal/")
        XCTAssertEqual(try json(sent.body) as NSDictionary, ["cookbook": 4])
    }

    func testSavingACookbookAgainIsADocumentedAnswerWithTheSameCopy() async throws {
        let first = CookbookTransport(status: 201, responseBody: Self.summary)
        let again = CookbookTransport(status: 200, responseBody: Self.summary)
        guard case .created(let created) = try await client(first).socialPostsSaveCookbookCreate(path: .init(id: 8)),
              case .ok(let repeated) = try await client(again).socialPostsSaveCookbookCreate(path: .init(id: 8)) else {
            return XCTFail("Both a new copy (201) and the existing one (200) must decode, not read as failures")
        }
        XCTAssertEqual(try created.body.json.id, try repeated.body.json.id)
        let log = await again.sent
        let sent = try XCTUnwrap(log.first)
        XCTAssertEqual(sent.method, .post)
        XCTAssertEqual(sent.path, "/api/v1/social/posts/8/save-cookbook/")
    }

    func testPublishedCookbookDecodesEveryRecipeWithExactNutrition() async throws {
        let transport = CookbookTransport(responseBody: #"""
        {"name":"Weeknight favorites","recipe_count":1,"recipes":[{"name":"Curry","cooking_instructions":"Simmer.",
         "ingredients":[{"name":"Rice","servings":"1.50","calories":"200.00","protein_grams":"4.25",
                         "carbohydrate_grams":"44.00","fat_grams":"0.50"}]}]}
        """#)
        guard case .ok(let response) = try await client(transport).socialPostsCookbookRetrieve(path: .init(id: 12)) else {
            return XCTFail("A visible publication answers 200")
        }
        let cookbook = try response.body.json
        XCTAssertEqual(cookbook.recipeCount, 1)
        let recipe = try XCTUnwrap(cookbook.recipes.first)
        XCTAssertEqual(recipe.cookingInstructions, "Simmer.")
        let rice = try XCTUnwrap(recipe.ingredients.first)
        // Strings on the wire, so no binary rounding before the app reads them.
        XCTAssertEqual([rice.servings, rice.calories, rice.proteinGrams, rice.carbohydrateGrams, rice.fatGrams],
                       ["1.50", "200.00", "4.25", "44.00", "0.50"])
        let sent = await transport.sent
        XCTAssertEqual(sent.first?.path, "/api/v1/social/posts/12/cookbook/")
    }

    // MARK: - Refusals

    func testFullCookbookRefusalReadsAsTheServersSentence() async throws {
        let sentence = "This cookbook is full. Choose another cookbook or create one (20 recipes maximum)."
        let transport = CookbookTransport(status: 400, responseBody: #"{"cookbook":["\#(sentence)"]}"#)
        let output = try await client(transport).socialPostsSaveMealCreate(
            path: .init(id: 31), body: .json(.init(cookbook: 4)))
        guard case .undocumented(let status, let payload) = output else { return XCTFail("A refusal is not a save") }
        let error = await RepbaseAPIHTTPError.decode(statusCode: status, payload: payload, unlabeled: ["cookbook", "post"])
        XCTAssertEqual(error.statusCode, 400)
        XCTAssertEqual(error.errorDescription, sentence, "No \"Cookbook:\" field label in front of a whole sentence")
    }

    func testDuplicateNameAndNonemptyDeleteRefusalsReadAsSentences() async throws {
        let duplicate = CookbookTransport(
            status: 400, responseBody: #"{"name":["You already have a cookbook with this name."]}"#)
        let created = try await client(duplicate).foodCookbooksCreate(
            headers: .init(idempotencyKey: UUID().uuidString), body: .json(.init(name: "breakfast")))
        guard case .undocumented(let status, let payload) = created else { return XCTFail("A duplicate is refused") }
        let nameError = await RepbaseAPIHTTPError.decode(statusCode: status, payload: payload, unlabeled: ["name", "cookbook"])
        XCTAssertEqual(nameError.errorDescription, "You already have a cookbook with this name.")

        let nonempty = CookbookTransport(
            status: 400, responseBody: #"{"cookbook":["Move or delete this cookbook's recipes before deleting it."]}"#)
        let deleted = try await client(nonempty).foodCookbooksDestroy(path: .init(id: 4))
        guard case .undocumented(let deleteStatus, let deletePayload) = deleted else {
            return XCTFail("A cookbook with recipes is not deleted")
        }
        let deleteError = await RepbaseAPIHTTPError.decode(
            statusCode: deleteStatus, payload: deletePayload, unlabeled: ["cookbook"])
        XCTAssertEqual(deleteError.errorDescription, "Move or delete this cookbook's recipes before deleting it.")
    }

    // MARK: - App models

    func testCookbookIsFullAtItsCapacity() {
        XCTAssertFalse(Cookbook(id: 1, name: "Lunches", recipeCount: 19, capacity: 20).isFull)
        XCTAssertTrue(Cookbook(id: 1, name: "Lunches", recipeCount: 20, capacity: 20).isFull)
        XCTAssertTrue(Cookbook(id: 1, name: "Lunches", recipeCount: 21, capacity: 20).isFull)
        XCTAssertFalse(Cookbook(id: 1, name: "Lunches", recipeCount: 20, capacity: 30).isFull,
                       "The server's capacity decides, not a number built into the app")
    }

    func testCookbookPostKindRoundTripsAndUnknownKindsAreKept() {
        XCTAssertEqual(PostKind("cookbook"), .cookbook)
        XCTAssertEqual(PostKind.cookbook.apiValue, "cookbook")
        XCTAssertEqual(PostKind("recipe_box"), .unknown("recipe_box"))
    }

    func testCookbookPostAndItsRepostAreDrawableButOfferNoMealSave() {
        let author = PostAuthor(id: 2, username: "cook", firstName: "Ana", lastName: "Cook")
        let summary = CookbookPostSummary(name: "Weeknight favorites", recipeCount: 3)
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let post = FeedPost(id: 10, author: author, kind: .cookbook, caption: "My dinners", visibility: .publicToAll,
                            createdAt: created, viewerFollowsAuthor: true, cookbook: summary)
        XCTAssertTrue(post.isRenderable)
        XCTAssertEqual(post.displayed.cookbook, summary)
        XCTAssertFalse(post.offersMealToSave)

        let original = RepostedPost(id: 10, author: author, kind: .cookbook, caption: "My dinners",
                                    createdAt: created, cookbook: summary)
        let repost = FeedPost(id: 11, author: PostAuthor(id: 3, username: "friend", firstName: "", lastName: ""),
                              kind: .repost, caption: "", visibility: .publicToAll, createdAt: created,
                              viewerFollowsAuthor: false, repostOf: original)
        XCTAssertTrue(repost.isRenderable)
        XCTAssertEqual(repost.displayed.cookbook, summary)
        XCTAssertEqual(repost.displayed.kind, .cookbook)

        let emptyRepost = FeedPost(id: 12, author: author, kind: .repost, caption: "", visibility: .publicToAll,
                                   createdAt: created, viewerFollowsAuthor: false,
                                   repostOf: RepostedPost(id: 13, author: author, kind: .cookbook, caption: "",
                                                          createdAt: created))
        XCTAssertFalse(emptyRepost.isRenderable, "A cookbook repost with no summary has nothing to draw")
    }
}
