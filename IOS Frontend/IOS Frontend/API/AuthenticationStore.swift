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
    case recoveryRequired
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
@MainActor
final class AuthenticationStore {
    let configuration: APIConfiguration

    private let tokenStore: any AuthenticationTokenStore
    private let defaults: UserDefaults
    private let sessionLoader: (@MainActor (String) async throws -> AuthenticatedUser)?
    private var sessionGeneration = UUID()
    private static let removalPendingKey = "authentication.credentialRemovalPending"
    var onSessionEnded: (() -> Void)?
    var onAccountDeleted: ((Int) -> Void)?
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
        tokenStore: any AuthenticationTokenStore = KeychainTokenStore(),
        defaults: UserDefaults = .standard,
        sessionLoader: (@MainActor (String) async throws -> AuthenticatedUser)? = nil
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.defaults = defaults
        self.sessionLoader = sessionLoader
    }

    func restoreSession() async {
        guard !isWorking else { return }
        let generation = UUID()
        sessionGeneration = generation
        isWorking = true
        defer { if sessionGeneration == generation { isWorking = false } }
        needsOnboarding = false
        phase = .checking
        errorMessage = nil

        do {
            if defaults.bool(forKey: Self.removalPendingKey) {
                clearLocalSession()
                return
            }
            guard let savedToken = try tokenStore.read() else {
                clearLocalSession()
                return
            }

            let user = try await loadRestoredUser(token: savedToken)
            guard sessionGeneration == generation, !Task.isCancelled else { return }
            token = savedToken
            phase = .signedIn(user)
        } catch {
            guard sessionGeneration == generation, !Task.isCancelled else { return }
            if Self.isRejectedSession(error) {
                clearLocalSession()
                errorMessage = "Your session has expired. Please sign in again."
            } else {
                phase = .recoveryRequired
                errorMessage = "We couldn't reconnect. Your saved login is safe. Check your connection and try again."
            }
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
        let outgoingToken = token
        clearLocalSession()
        let generation = sessionGeneration
        isWorking = true
        defer { if sessionGeneration == generation { isWorking = false } }
        if let outgoingToken {
            do {
                let client = try authenticatedClient(token: outgoingToken)
                _ = try await client.authLogoutCreate()
            } catch {
                // Local credentials are still cleared if the server is offline
                // or the token has already expired.
            }
        }
    }

    private func clearLocalSession() {
        sessionGeneration = UUID()
        // A failed Keychain delete must not restore a logged-out account later.
        defaults.set(true, forKey: Self.removalPendingKey)
        onSessionEnded?()
        token = nil
        needsOnboarding = false
        isWorking = false
        phase = .signedOut
        do {
            try tokenStore.delete()
            defaults.removeObject(forKey: Self.removalPendingKey)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Replaces the current API credential without ending the user's session.
    func rotateSessionToken() async throws {
        guard !isWorking else { return }
        guard let token else { return }
        let generation = sessionGeneration
        isWorking = true
        errorMessage = nil
        defer { if sessionGeneration == generation { isWorking = false } }

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
            guard sessionGeneration == generation, !Task.isCancelled else { return }
            try tokenStore.save(response.token)
            self.token = response.token
            phase = .signedIn(Self.map(response.user.value1))
        } catch {
            guard sessionGeneration == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func deleteAccount() async throws {
        guard !isWorking else { return }
        guard let token else { return }
        let generation = sessionGeneration
        isWorking = true
        errorMessage = nil
        defer { if sessionGeneration == generation { isWorking = false } }

        do {
            let client = try authenticatedClient(token: token)
            let output = try await client.meDestroy(.init())
            guard sessionGeneration == generation, !Task.isCancelled else { return }
            switch output {
            case .noContent:
                if case .signedIn(let user) = phase { onAccountDeleted?(user.id) }
                clearLocalSession()
            case .undocumented(let statusCode, let payload):
                throw await RepbaseAPIHTTPError.decode(
                    statusCode: statusCode,
                    payload: payload
                )
            }
        } catch {
            guard sessionGeneration == generation, !Task.isCancelled else { return }
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
        let generation = sessionGeneration
        isWorking = true
        errorMessage = nil
        defer { if sessionGeneration == generation { isWorking = false } }

        do {
            let response = try await request()
            guard sessionGeneration == generation, !Task.isCancelled else { return }
            try tokenStore.save(response.token)
            defaults.removeObject(forKey: Self.removalPendingKey)
            token = response.token
            phase = .signedIn(Self.map(response.user.value1))
        } catch {
            guard sessionGeneration == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            phase = .signedOut
        }
    }

    private static func isRejectedSession(_ error: Error) -> Bool {
        if let response = error as? RepbaseAPIHTTPError { return response.statusCode == 401 }
        if let response = error as? APIServiceError,
           case .undocumentedStatus(401) = response { return true }
        return false
    }

    private func loadRestoredUser(token: String) async throws -> AuthenticatedUser {
        if let sessionLoader { return try await sessionLoader(token) }
        let client = try authenticatedClient(token: token)
        let output = try await client.meRetrieve()
        switch output {
        case .ok(let response):
            return Self.map(try response.body.json)
        case .undocumented(let statusCode, let payload):
            throw await RepbaseAPIHTTPError.decode(statusCode: statusCode, payload: payload)
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
