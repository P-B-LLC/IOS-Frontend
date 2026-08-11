//
//  AuthenticationStore.swift
//  IOS Frontend
//
//  Login, registration, token restoration, and logout through the OAS client.
//

import Foundation
import Observation
import RepbaseAPI

struct AuthenticatedUser: Equatable, Sendable {
    let id: Int
    let username: String
    let firstName: String
    let lastName: String

    var displayName: String {
        let fullName = "\(firstName) \(lastName)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fullName.isEmpty ? username : fullName
    }
}

enum AuthenticationPhase: Equatable {
    case checking
    case signedOut
    case signedIn(AuthenticatedUser)
}

enum APIServiceError: LocalizedError {
    case undocumentedStatus(Int)
    case malformedResponse
    case untrustedPaginationURL
    case missingServerIdentifier(String)
    case partialWorkoutCreation(String)

    var errorDescription: String? {
        switch self {
        case .undocumentedStatus(let status):
            if status == 401 {
                return "The username, password, or saved session is not valid."
            }
            return "The server returned an unexpected response (HTTP \(status))."
        case .malformedResponse:
            return "The server returned data the app could not understand."
        case .untrustedPaginationURL:
            return "The server returned an invalid pagination link."
        case .missingServerIdentifier(let item):
            return "\(item) has not been saved to the server yet."
        case .partialWorkoutCreation(let detail):
            return "The workout was only partially saved. \(detail)"
        }
    }
}

@Observable
final class AuthenticationStore {
    let configuration: APIConfiguration

    private let tokenStore: KeychainTokenStore
    private(set) var phase: AuthenticationPhase = .checking
    private(set) var token: String?
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    init(
        configuration: APIConfiguration,
        tokenStore: KeychainTokenStore = KeychainTokenStore()
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
    }

    func restoreSession() async {
        phase = .checking
        errorMessage = nil

        do {
            guard let savedToken = try tokenStore.read() else {
                phase = .signedOut
                return
            }

            let client = try authenticatedClient(token: savedToken)
            let output = try await client.meRetrieve()
            let user: Components.Schemas.RepbaseUser
            switch output {
            case .ok(let response):
                user = try response.body.json
            case .undocumented(let statusCode, let payload):
                throw await RepbaseAPIHTTPError.decode(
                    statusCode: statusCode,
                    payload: payload
                )
            }

            token = savedToken
            phase = .signedIn(Self.map(user))
        } catch {
            try? tokenStore.delete()
            token = nil
            phase = .signedOut
            errorMessage = "Please sign in again. \(error.localizedDescription)"
        }
    }

    func login(username: String, password: String) async {
        await authenticate {
            let client = try anonymousClient()
            let output = try await client.authLoginCreate(
                body: .json(
                    Components.Schemas.LoginRequest(
                        username: username,
                        password: password
                    )
                )
            )
            switch output {
            case .ok(let response):
                return try response.body.json
            case .undocumented(let statusCode, let payload):
                throw await RepbaseAPIHTTPError.decode(
                    statusCode: statusCode,
                    payload: payload
                )
            }
        }
    }

    func register(
        username: String,
        email: String,
        password: String,
        firstName: String,
        lastName: String
    ) async {
        await authenticate {
            let client = try anonymousClient()
            let output = try await client.authRegisterCreate(
                body: .json(
                    Components.Schemas.RegisterRequest(
                        username: username,
                        email: email,
                        password: password,
                        firstName: firstName,
                        lastName: lastName
                    )
                )
            )
            switch output {
            case .created(let response):
                return try response.body.json
            case .undocumented(let statusCode, let payload):
                throw await RepbaseAPIHTTPError.decode(
                    statusCode: statusCode,
                    payload: payload
                )
            }
        }
    }

    func signOut() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        if let token {
            do {
                let client = try authenticatedClient(token: token)
                _ = try await client.authLogoutCreate()
            } catch {
                // Local credentials are still cleared if the server is offline
                // or the token has already expired.
            }
        }

        do {
            try tokenStore.delete()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        token = nil
        phase = .signedOut
    }

    func clearError() {
        errorMessage = nil
    }

    private func authenticate(
        _ request: () async throws -> Components.Schemas.AuthResponse
    ) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let response = try await request()
            try tokenStore.save(response.token)
            token = response.token
            phase = .signedIn(Self.map(response.user.value1))
        } catch {
            errorMessage = error.localizedDescription
            phase = .signedOut
        }
    }

    private func anonymousClient() throws -> Client {
        try RepbaseAPIClientFactory.makeAnonymous(
            serverURL: configuration.serverURL,
            allowInsecureLocalhost: configuration.allowsInsecureLocalhost
        )
    }

    private func authenticatedClient(token: String) throws -> Client {
        try RepbaseAPIClientFactory.makeAuthenticated(
            serverURL: configuration.serverURL,
            token: token,
            allowInsecureLocalhost: configuration.allowsInsecureLocalhost
        )
    }

    private static func map(
        _ user: Components.Schemas.RepbaseUser
    ) -> AuthenticatedUser {
        AuthenticatedUser(
            id: user.id,
            username: user.username,
            firstName: user.firstName,
            lastName: user.lastName
        )
    }
}
