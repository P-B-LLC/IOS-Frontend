import Foundation
import RepbaseAPI

/// Wire operations are generated from the backend contract, never cached locally.
@MainActor
enum AccountSafetyConsent {
    static let version = "2026-10-17"

    static func granted(client: Client) async throws -> Bool {
        switch try await client.safetyConsentRetrieve() {
        case .ok(let response):
            let choice = try response.body.json
            guard choice.version == version else { throw APIServiceError.malformedResponse }
            return choice.granted
        case .undocumented(let status, _):
            throw APIServiceError.undocumentedStatus(status)
        }
    }

    static func set(_ granted: Bool, client: Client) async throws {
        switch try await client.safetyConsentUpdate(body: .json(.init(version: version, granted: granted))) {
        case .ok(let response):
            let choice = try response.body.json
            guard choice.version == version, choice.granted == granted else {
                throw APIServiceError.malformedResponse
            }
        case .undocumented(let status, _):
            throw APIServiceError.undocumentedStatus(status)
        }
    }

    static func require(client: Client) async throws {
        // Never present a permission dialog from a posting/profile operation.
        guard try await granted(client: client) else { throw ReviewDisabled() }
    }

    struct ReviewDisabled: LocalizedError {
        var errorDescription: String? {
            "Safety review is disabled for your account. Manage it in Settings before sharing."
        }
    }
}
