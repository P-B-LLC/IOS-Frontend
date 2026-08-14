//
//  RepbaseAPIClient.swift
//  RepbaseAPI
//
//  Construction and authentication for the OAS-generated API client.
//

import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

public enum RepbaseAPIClientError: LocalizedError {
    case invalidServerURL
    case insecureServerURL
    case serverURLMustBeOrigin
    case emptyToken
    case insecureLocalhostOverrideRequired

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The Repbase API URL must include a valid host."
        case .insecureServerURL:
            return "The Repbase API URL must use HTTPS."
        case .serverURLMustBeOrigin:
            return "The Repbase API URL must be an origin without a path, query, or fragment."
        case .emptyToken:
            return "The Repbase API token cannot be empty."
        case .insecureLocalhostOverrideRequired:
            return "HTTP is permitted only for an explicitly enabled localhost development server."
        }
    }
}

/// Reads the ISO8601 timestamps the backend actually sends.
///
/// Django REST Framework includes fractional seconds only when they are
/// non-zero, so the same field arrives as either
/// `2026-08-14T20:40:12.345678Z` or `2026-08-14T20:40:12Z`. The runtime's
/// default transcoder is configured for internet date-time without fractional
/// seconds and rejects the first form outright, which fails the whole response
/// with "Expected date string to be ISO8601-formatted".
struct RepbaseDateTranscoder: DateTranscoder {
    // Configured once here and only read afterwards. Formatting and parsing on
    // ISO8601DateFormatter is thread-safe; the type simply predates Sendable.
    // Shared instances matter because a single response can carry thousands of
    // timestamps, as a recorded GPS route does.
    nonisolated(unsafe) private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func encode(_ date: Date) throws -> String {
        Self.withFractionalSeconds.string(from: date)
    }

    func decode(_ string: String) throws -> Date {
        if let date = Self.withFractionalSeconds.date(from: string) {
            return date
        }
        if let date = Self.withoutFractionalSeconds.date(from: string) {
            return date
        }
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: [],
                debugDescription: "Expected an ISO8601 date-time, got \"\(string)\"."
            )
        )
    }
}

/// Creates clients whose operations and wire types are generated from
/// `API/openapi.yaml` by the Swift OpenAPI Generator build plugin.
public enum RepbaseAPIClientFactory {
    /// Shared by every client so anonymous and authenticated calls decode
    /// timestamps identically.
    private static var configuration: Configuration {
        Configuration(dateTranscoder: RepbaseDateTranscoder())
    }

    /// Used only for the anonymous login and registration operations.
    public static func makeAnonymous(
        serverURL: URL,
        allowInsecureLocalhost: Bool = false
    ) throws -> Client {
        try validate(
            serverURL: serverURL,
            allowInsecureLocalhost: allowInsecureLocalhost
        )
        return Client(
            serverURL: serverURL,
            configuration: configuration,
            transport: URLSessionTransport()
        )
    }

    /// Used for every protected operation after loading the opaque token from
    /// Keychain. The OAS defines an API-key header and requires the `Token`
    /// prefix, which generated clients do not add automatically.
    public static func makeAuthenticated(
        serverURL: URL,
        token: String,
        allowInsecureLocalhost: Bool = false
    ) throws -> Client {
        try validate(
            serverURL: serverURL,
            allowInsecureLocalhost: allowInsecureLocalhost
        )

        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw RepbaseAPIClientError.emptyToken }

        return Client(
            serverURL: serverURL,
            configuration: configuration,
            transport: URLSessionTransport(),
            middlewares: [TokenAuthenticationMiddleware(token: token)]
        )
    }

    private static func validate(
        serverURL: URL,
        allowInsecureLocalhost: Bool
    ) throws {
        guard serverURL.host?.isEmpty == false else {
            throw RepbaseAPIClientError.invalidServerURL
        }
        let scheme = serverURL.scheme?.lowercased()
        if scheme != "https" {
            if scheme == "http", isLoopbackHost(serverURL.host) {
                guard allowInsecureLocalhost else {
                    throw RepbaseAPIClientError.insecureLocalhostOverrideRequired
                }
            } else {
                throw RepbaseAPIClientError.insecureServerURL
            }
        }
        guard serverURL.path.isEmpty || serverURL.path == "/",
              serverURL.query == nil,
              serverURL.fragment == nil,
              serverURL.user == nil,
              serverURL.password == nil else {
            throw RepbaseAPIClientError.serverURLMustBeOrigin
        }
    }

    private static func isLoopbackHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
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
