import Foundation
import XCTest
@testable import AccountSafety

@MainActor
private final class MemoryTokens: AuthenticationTokenStore {
    var value: String? = "test-only-opaque-value"
    var deletionFails = false
    var deletes = 0
    func read() throws -> String? { value }
    func save(_ token: String) throws { value = token }
    func delete() throws {
        deletes += 1
        if deletionFails { throw CocoaError(.fileWriteNoPermission) }
        value = nil
    }
}

final class AuthenticationSafetyTests: XCTestCase {
    private let user = AuthenticatedUser(id: 1, username: "tester", firstName: "Test", lastName: "User")

    @MainActor private func makeStore(
        tokens: MemoryTokens,
        defaults: UserDefaults? = nil,
        loader: @escaping @MainActor (String) async throws -> AuthenticatedUser
    ) -> AuthenticationStore {
        AuthenticationStore(
            configuration: APIConfiguration(serverURL: URL(string: "https://example.invalid/")!, allowsInsecureLocalhost: false),
            tokenStore: tokens,
            defaults: defaults ?? UserDefaults(suiteName: UUID().uuidString)!,
            sessionLoader: loader
        )
    }

    @MainActor func testOfflineTimeoutAndServerFailuresKeepCredentials() async {
        let failures: [Error] = [URLError(.notConnectedToInternet), URLError(.timedOut), APIServiceError.undocumentedStatus(500), APIServiceError.malformedResponse, APIServiceError.undocumentedStatus(403)]
        for failure in failures {
            let tokens = MemoryTokens()
            let store = makeStore(tokens: tokens) { _ in throw failure }
            await store.restoreSession()
            XCTAssertEqual(store.phase, .recoveryRequired)
            XCTAssertNotNil(tokens.value)
            XCTAssertNil(store.token)
            XCTAssertEqual(tokens.deletes, 0)
            XCTAssertFalse(store.isWorking)
        }
    }

    @MainActor func testOnlyAuthenticationRejectionDeletesCredentials() async {
        let tokens = MemoryTokens()
        let store = makeStore(tokens: tokens) { _ in throw APIServiceError.undocumentedStatus(401) }
        var cleared = false
        store.onSessionEnded = { cleared = true }
        await store.restoreSession()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(tokens.value)
        XCTAssertTrue(cleared)
    }

    @MainActor func testRetryRestoresWithoutEnteringPasswordAgain() async {
        let tokens = MemoryTokens()
        var shouldFail = true
        let user = self.user
        let store = makeStore(tokens: tokens) { _ in
            if shouldFail { throw URLError(.notConnectedToInternet) }
            return user
        }
        await store.restoreSession()
        shouldFail = false
        await store.restoreSession()
        XCTAssertEqual(store.phase, .signedIn(user))
        XCTAssertEqual(store.token, tokens.value)
    }

    @MainActor func testLogoutRejectsAnOlderRestoreResponse() async {
        let tokens = MemoryTokens()
        var response: CheckedContinuation<AuthenticatedUser, Error>?
        let store = makeStore(tokens: tokens) { _ in
            try await withCheckedThrowingContinuation { response = $0 }
        }
        let restoring = Task { await store.restoreSession() }
        while response == nil { await Task.yield() }
        var cleared = false
        store.onSessionEnded = { cleared = true }
        await store.signOut() // No published token: this never contacts a server.
        response?.resume(returning: user)
        await restoring.value
        XCTAssertTrue(cleared)
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.token)
        XCTAssertNil(tokens.value)
    }

    @MainActor func testFailedKeychainDeleteCannotRestoreOnNextLaunch() async {
        let tokens = MemoryTokens()
        tokens.deletionFails = true
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let user = self.user
        let first = makeStore(tokens: tokens, defaults: defaults) { _ in user }
        await first.signOut()
        var requested = false
        let next = makeStore(tokens: tokens, defaults: defaults) { _ in
            requested = true
            return user
        }
        await next.restoreSession()
        XCTAssertFalse(requested)
        XCTAssertEqual(next.phase, .signedOut)
        tokens.deletionFails = false
        await next.restoreSession()
        XCTAssertNil(tokens.value)
    }
}
