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
            return "The Rytivo API URL must include a valid host."
        case .insecureServerURL:
            return "The Rytivo API URL must use HTTPS."
        case .serverURLMustBeOrigin:
            return "The Rytivo API URL must be an origin without a path, query, or fragment."
        case .emptyToken:
            return "The Rytivo API token cannot be empty."
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
            transport: URLSessionTransport(),
            // Registration is a submission too: a username and a display name
            // are public text, and they go through review like anything else.
            middlewares: [ModerationConsentMiddleware(), ModerationErrorMiddleware()]
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
            middlewares: [TokenAuthenticationMiddleware(token: token), ModerationConsentMiddleware(), ModerationErrorMiddleware()]
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

/// Says which disclosure this build implements.
///
/// The server refuses to send anything for review without it, and refuses a
/// version it does not recognise. That is a gate on the *client*, which is the
/// only thing a server can actually check: whether a particular human tapped
/// Allow is not provable over HTTP, since any caller can send any header. What
/// this does rule out is a build from before the consent flow existed, and a
/// script that never had one -- which is what could previously cause
/// third-party processing with nobody asked.
///
/// The per-submission question is still real and still enforced, one layer up:
/// `ModerationConsent.require()` throws when somebody cancels, so the request
/// is never made and the header never gets the chance to matter.
///
/// Bump this with the server when the wording changes. Agreement to the old
/// disclosure is not agreement to a new one, and an old build should stop
/// being able to submit rather than quietly keep going.
enum ModerationDisclosure {
    static let version = "2026-09-15"
}

private struct ModerationConsentMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.init("X-Moderation-Consent")!] = ModerationDisclosure.version
        return try await next(request, body, baseURL)
    }
}

/// A refusal the server explained, rather than a status code.
///
/// The backend already sends something a person can act on -- why the content
/// was refused, where to appeal, or that safety checks are down and the
/// content was not published. Every one of those was arriving as "unexpected
/// response (HTTP 400)", because the generated client folds anything the
/// contract does not enumerate into `.undocumented` and the call sites throw
/// the number.
///
/// Fixing that at 128 call sites would be 128 chances to do it differently.
/// This reads the body once, in one place, and throws something the UI can
/// show and decide about: `isTemporary` is the difference between "try again
/// in a minute" and "this will not work until you change it".
public struct ModerationError: LocalizedError, Sendable {
    public let code: String
    public let detail: String
    public let isTemporary: Bool

    public var errorDescription: String? { detail }

    /// Only an outage is worth offering a retry for. Offering one after a
    /// refusal invites somebody to press it until it works, and it will not.
    public var isRetryable: Bool { isTemporary }
}

private struct ModerationErrorMiddleware: ClientMiddleware {
    private static let known: [String: Bool] = [
        "moderation_rejected": false,
        "moderation_consent_required": false,
        "moderation_unavailable": true,
    ]

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        guard response.status.code >= 400, let responseBody else {
            return (response, responseBody)
        }
        // Buffered rather than consumed: anything this does not recognise has
        // to reach the caller unread and unchanged.
        guard let bytes = try? await Data(collecting: responseBody, upTo: 64 * 1024) else {
            return (response, responseBody)
        }
        if let payload = try? JSONDecoder().decode(ServerRefusal.self, from: bytes),
           let code = payload.code,
           let isTemporary = Self.known[code] {
            throw ModerationError(
                code: code,
                detail: payload.detail ?? "This could not be published.",
                isTemporary: isTemporary
            )
        }
        return (response, HTTPBody(bytes))
    }
}

private struct ServerRefusal: Decodable {
    let detail: String?
    let code: String?
}
