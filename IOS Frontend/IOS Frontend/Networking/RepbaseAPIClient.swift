//
//  RepbaseAPIClient.swift
//  IOS Frontend
//
//  Construction and authentication for the OAS-generated API client.
//

import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

enum RepbaseAPIClientError: LocalizedError {
    case invalidServerURL
    case insecureServerURL
    case serverURLMustBeOrigin
    case emptyToken

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The Repbase API URL must include a valid host."
        case .insecureServerURL:
            return "The Repbase API URL must use HTTPS."
        case .serverURLMustBeOrigin:
            return "The Repbase API URL must be an origin without a path, query, or fragment."
        case .emptyToken:
            return "The Repbase API token cannot be empty."
        }
    }
}

/// Creates clients whose operations and wire types are generated from
/// `API/openapi.yaml` by the Swift OpenAPI Generator build plugin.
enum RepbaseAPIClientFactory {
    /// Used only for the anonymous login and registration operations.
    static func makeAnonymous(serverURL: URL) throws -> Client {
        try validate(serverURL: serverURL)
        return Client(
            serverURL: serverURL,
            transport: URLSessionTransport()
        )
    }

    /// Used for every protected operation after loading the opaque token from
    /// Keychain. The OAS defines an API-key header and requires the `Token`
    /// prefix, which generated clients do not add automatically.
    static func makeAuthenticated(serverURL: URL, token: String) throws -> Client {
        try validate(serverURL: serverURL)

        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw RepbaseAPIClientError.emptyToken }

        return Client(
            serverURL: serverURL,
            transport: URLSessionTransport(),
            middlewares: [TokenAuthenticationMiddleware(token: token)]
        )
    }

    private static func validate(serverURL: URL) throws {
        guard serverURL.host?.isEmpty == false else {
            throw RepbaseAPIClientError.invalidServerURL
        }
        guard serverURL.scheme?.lowercased() == "https" else {
            throw RepbaseAPIClientError.insecureServerURL
        }
        guard serverURL.path.isEmpty || serverURL.path == "/",
              serverURL.query == nil,
              serverURL.fragment == nil,
              serverURL.user == nil,
              serverURL.password == nil else {
            throw RepbaseAPIClientError.serverURLMustBeOrigin
        }
    }
}

/// Injects the exact token header required by `components.securitySchemes`.
private struct TokenAuthenticationMiddleware: ClientMiddleware {
    private let authorizationValue: String

    init(token: String) {
        authorizationValue = "Token \(token)"
    }

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.authorization] = authorizationValue
        return try await next(request, body, baseURL)
    }
}
