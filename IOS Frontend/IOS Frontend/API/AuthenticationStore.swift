//
//  AuthenticationStore.swift
//  IOS Frontend
//
//  Login, registration, token restoration, and logout through the OAS client.
//

import Foundation
import Observation
import OpenAPIRuntime
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

/// Too many reset codes asked for in too short a time.
struct PasswordResetThrottled: LocalizedError {
    var errorDescription: String? {
        "Too many reset attempts. Wait an hour and try again -- and check your "
            + "spam folder in the meantime."
    }
}

@Observable
final class AuthenticationStore {
    let configuration: APIConfiguration

    private let tokenStore: KeychainTokenStore
    private(set) var phase: AuthenticationPhase = .checking
    private(set) var token: String?
    private(set) var isWorking = false
    /// Kept apart from `isWorking`. The reset sheet sits over the sign-in
    /// screen, and one spinner driving both buttons would grey out a screen
    /// the user cannot see anyway.
    private(set) var isResettingPassword = false
    private(set) var errorMessage: String?
    /// True only for the account created in this app session. Returning users
    /// should never be forced through first-run questions after every launch.
    private(set) var needsOnboarding = false

    init(
        configuration: APIConfiguration,
        tokenStore: KeychainTokenStore = KeychainTokenStore()
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
    }

    func restoreSession() async {
        needsOnboarding = false
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
        needsOnboarding = false
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
        if token != nil {
            needsOnboarding = true
        }
    }

    func completeOnboarding() {
        needsOnboarding = false
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
        needsOnboarding = false
        phase = .signedOut
    }

    /// Replaces the current API credential without ending the user's session.
    func rotateSessionToken() async throws {
        guard !isWorking else { return }
        guard let token else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let client = try authenticatedClient(token: token)
            let output = try await client.authRotateTokenCreate()
            let response: Components.Schemas.AuthResponse
            switch output {
            case .ok(let success):
                response = try success.body.json
            case .undocumented(let statusCode, let payload):
                throw await RepbaseAPIHTTPError.decode(
                    statusCode: statusCode,
                    payload: payload
                )
            }
            try tokenStore.save(response.token)
            self.token = response.token
            phase = .signedIn(Self.map(response.user.value1))
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func deleteAccount() async throws {
        guard !isWorking else { return }
        guard let token else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let client = try authenticatedClient(token: token)
            let output = try await client.meDestroy(.init())
            switch output {
            case .noContent:
                try tokenStore.delete()
                self.token = nil
                phase = .signedOut
            case .undocumented(let statusCode, let payload):
                throw await RepbaseAPIHTTPError.decode(
                    statusCode: statusCode,
                    payload: payload
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Asks the server to email a reset code.
    ///
    /// Succeeds whether or not the address belongs to an account: the server
    /// deliberately answers the same way either way, so there is nothing here
    /// to branch on and nothing to tell the caller.
    func requestPasswordReset(email: String) async throws {
        isResettingPassword = true
        defer { isResettingPassword = false }

        let client = try anonymousClient()
        let output = try await client.authPasswordResetCreate(
            body: .json(
                Components.Schemas.PasswordResetRequestRequest(email: email)
            )
        )
        switch output {
        case .noContent:
            return
        case .undocumented(let statusCode, let payload):
            throw await Self.resetError(statusCode: statusCode, payload: payload)
        }
    }

    /// Spends a code on a new password and signs in with what comes back.
    ///
    /// The server issues a fresh token and invalidates every other one, so the
    /// response is already a complete session. Sending the user back to type
    /// the password they chose ten seconds ago would be busywork.
    func confirmPasswordReset(
        email: String,
        code: String,
        newPassword: String
    ) async throws {
        isResettingPassword = true
        defer { isResettingPassword = false }

        let client = try anonymousClient()
        let output = try await client.authPasswordResetConfirmCreate(
            body: .json(
                Components.Schemas.PasswordResetConfirmRequest(
                    email: email,
                    code: code,
                    newPassword: newPassword
                )
            )
        )

        let response: Components.Schemas.AuthResponse
        switch output {
        case .ok(let success):
            response = try success.body.json
        case .undocumented(let statusCode, let payload):
            throw await Self.resetError(statusCode: statusCode, payload: payload)
        }

        try tokenStore.save(response.token)
        token = response.token
        needsOnboarding = false
        errorMessage = nil
        phase = .signedIn(Self.map(response.user.value1))
    }

    /// The shared decoder has no wording for 429, and the reset flow is where
    /// somebody actually meets one -- asking again because the first email has
    /// not arrived yet is the obvious thing to do.
    private static func resetError(
        statusCode: Int,
        payload: UndocumentedPayload
    ) async -> Error {
        if statusCode == 429 {
            return PasswordResetThrottled()
        }
        return await RepbaseAPIHTTPError.decode(
            statusCode: statusCode,
            payload: payload
        )
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
