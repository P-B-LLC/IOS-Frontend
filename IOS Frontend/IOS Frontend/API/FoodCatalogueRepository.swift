import Foundation
import OpenAPIRuntime
import RepbaseAPI

/// Search identities come from the current public index. Nutrition comes only
/// from the selected product's complete, basis-aware barcode detail response.
actor FoodDatabaseRepository {
    private let client: Client

    init(configuration: APIConfiguration, token: String) throws {
        client = try RepbaseAPIClientFactory.makeAuthenticated(
            serverURL: configuration.serverURL, token: token,
            allowInsecureLocalhost: configuration.allowsInsecureLocalhost
        )
    }

    /// Uses the same generated transport in focused tests, without credentials.
    init(client: Client) { self.client = client }

    func search(_ query: String) async throws -> [FoodCatalogueCandidate] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return [] }
        try Task.checkCancellation()

        if term.lowercased().hasPrefix("barcode:") {
            guard let code = FoodBarcode.validated(String(term.dropFirst(8))) else { return [] }
            return try await barcodeResults(code)
        }
        if let code = FoodBarcode.validated(term) {
            return try await barcodeResults(code)
        }

        let output = try await client.foodDiscoverList(query: .init(q: term))
        switch output {
        case .ok(let response):
            try Task.checkCancellation()
            return try response.body.json.map { payload in
                FoodCatalogueCandidate(sourceID: payload.sourceId, name: payload.name, brand: payload.brand)
            }
        case .undocumented(let statusCode, let payload):
            guard FoodCataloguePolicy.allowsLegacyFallback(statusCode: statusCode) else {
                throw await Self.failure(statusCode: statusCode, payload: payload)
            }
            // Never fall back for throttle/auth/outage responses: that would
            // double the provider load at exactly the time it cannot cope.
            return try await productResults(term).map { FoodCatalogueCandidate(verified: $0) }
        }
    }

    func details(for candidate: FoodCatalogueCandidate) async throws -> FoodDatabaseResult? {
        try Task.checkCancellation()
        if let verified = candidate.verifiedResult { return verified }
        guard let code = FoodCataloguePolicy.barcode(sourceID: candidate.sourceID) else { return nil }
        let products = try await productResults("barcode:" + code)
        return products.first { $0.sourceID == candidate.sourceID }
    }

    private func barcodeResults(_ code: String) async throws -> [FoodCatalogueCandidate] {
        try await productResults("barcode:" + code)
            .filter { $0.sourceID == "off:" + code }
            .map { FoodCatalogueCandidate(verified: $0) }
    }

    private func productResults(_ term: String) async throws -> [FoodDatabaseResult] {
        try Task.checkCancellation()
        let output = try await client.foodSearchList(query: .init(q: term))
        switch output {
        case .ok(let response):
            try Task.checkCancellation()
            return try response.body.json.compactMap { payload in
                guard let nutrition = FoodCataloguePolicy.nutrition(
                    calories: payload.calories, protein: payload.proteinGrams,
                    carbs: payload.carbohydrateGrams, fat: payload.fatGrams
                ), !payload.servingDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let candidate = FoodCatalogueCandidate(sourceID: payload.sourceId, name: payload.name, brand: payload.brand)
                return FoodDatabaseResult(
                    sourceID: payload.sourceId, servingDescription: payload.servingDescription,
                    entry: FoodEntry(name: FoodCataloguePolicy.diaryName(candidate.title), servings: 1, nutritionPerServing: nutrition)
                )
            }
        case .undocumented(let statusCode, let payload):
            throw await Self.failure(statusCode: statusCode, payload: payload)
        }
    }

    private static func failure(statusCode: Int, payload: UndocumentedPayload) async -> Error {
        if let classified = FoodCataloguePolicy.failure(
            statusCode: statusCode,
            retryAfter: payload.headerFields[.init("Retry-After")!]
        ) { return classified }
        return await RepbaseAPIHTTPError.decode(statusCode: statusCode, payload: payload)
    }
}
