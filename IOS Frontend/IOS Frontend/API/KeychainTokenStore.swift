//
//  KeychainTokenStore.swift
//  IOS Frontend
//
//  Secure storage for the opaque Repbase API token.
//

import Foundation
import Security

enum KeychainTokenStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidStoredValue

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed with status \(status)."
        case .invalidStoredValue:
            return "The saved authentication token is invalid."
        }
    }
}

@MainActor
protocol AuthenticationTokenStore {
    func read() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

struct KeychainTokenStore: Sendable, AuthenticationTokenStore {
    private let service: String
    private let account: String

    // Nonisolated so it can still be spelled as a default argument. Conforming
    // to the main-actor protocol above isolates the whole type, and Swift
    // evaluates default arguments outside that isolation.
    nonisolated init(
        // Tracks the bundle identifier by hand, because it is a label rather
        // than a lookup. Changing the identifier already orphans what is
        // stored here — iOS scopes Keychain items by an access group derived
        // from it — so leaving this string on the old name would only make
        // the next reader think the two were connected.
        service: String = "com.pbllc.rytivo.api",
        account: String = "authentication-token"
    ) {
        self.service = service
        self.account = account
    }

#if DEBUG
    /// Writes, reads back and removes a throwaway value, and reports what
    /// happened.
    ///
    /// Whether a session survives relaunching comes down to whether this build
    /// can use the Keychain at all, which depends on how it was signed rather
    /// than on anything in the app. Reading that off the entitlements is
    /// unreliable, so this asks the Keychain directly.
    static func diagnose() -> String {
        let probe = KeychainTokenStore(
            service: "com.pbllc.rytivo.keychain-check",
            account: "probe"
        )
        do {
            try probe.save("probe-value")
            let read = try probe.read()
            try probe.delete()
            return read == "probe-value"
                ? "KEYCHAIN-CHECK works: a session will survive relaunching."
                : "KEYCHAIN-CHECK unavailable: nothing was stored, so every launch needs a sign-in."
        } catch {
            return "KEYCHAIN-CHECK failed: \(error.localizedDescription)"
        }
    }
#endif

    func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
#if targetEnvironment(simulator)
        // A command-line simulator build with code signing disabled has no
        // Keychain entitlement. Treat that exactly like a first launch; normal
        // Xcode-signed runs still store and restore only through Keychain.
        if status == errSecMissingEntitlement { return nil }
#endif
        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw KeychainTokenStoreError.invalidStoredValue
        }
        return token
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if isUnavailableOnSimulator(updateStatus) { return }

        if updateStatus == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            if isUnavailableOnSimulator(addStatus) { return }
            guard addStatus == errSecSuccess else {
                throw KeychainTokenStoreError.unexpectedStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw KeychainTokenStoreError.unexpectedStatus(updateStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if isUnavailableOnSimulator(status) { return }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
    }

    /// A simulator build produced without code signing carries no Keychain
    /// entitlement, so every item operation returns `errSecMissingEntitlement`.
    ///
    /// Reading already treats that as "nothing stored". Writing has to match:
    /// signing in saves the token before the session is marked active, so
    /// throwing here blocks sign-in outright on a build that is otherwise
    /// perfectly usable. The session simply lasts until the app is relaunched.
    /// Device and Xcode-signed builds are unaffected and still require the
    /// Keychain to work.
    private func isUnavailableOnSimulator(_ status: OSStatus) -> Bool {
#if targetEnvironment(simulator)
        return status == errSecMissingEntitlement
#else
        return false
#endif
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
