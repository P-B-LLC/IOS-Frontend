import Foundation
import RepbaseAPI

/// Whether this account has finished the iPhone app's welcome guide.
///
/// Only decides whether the guide opens by itself; replaying it from
/// Settings asks nothing.
actor GuideAPIRepository {
    private let client: Client

    init(configuration: APIConfiguration, token: String) throws {
        client = try RepbaseAPIClientFactory.makeAuthenticated(
            serverURL: configuration.serverURL,
            token: token,
            allowInsecureLocalhost: configuration.allowsInsecureLocalhost
        )
    }

    func isCompleted() async throws -> Bool {
        switch try await client.guideRetrieve(path: .init(surface: .ios)) {
        case .ok(let response):
            return try response.body.json.completed
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }

    /// Finished or skipped: it stops opening by itself on any iPhone.
    func markCompleted() async throws {
        switch try await client.guideUpdate(path: .init(surface: .ios), body: .json(.init(completed: true))) {
        case .ok:
            return
        case .undocumented(let statusCode, _):
            throw APIServiceError.undocumentedStatus(statusCode)
        }
    }
}
