import SwiftUI
import RepbaseAPI

struct SafetyConsentSettings: View {
    @Environment(AuthenticationStore.self) private var authentication
    @State private var granted: Bool?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Safety review").font(.headline)
            Text("Manage safety review for content you share. Processing details are in the Privacy Policy you accepted.")
                .font(.footnote).foregroundStyle(.secondary)
            if busy { ProgressView() }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            if let granted {
                Button(granted ? "Withdraw safety-review permission" : "Review and allow") {
                    Task { await update(withdraw: granted) }
                }.disabled(busy)
            } else if !busy {
                Button("Retry") { Task { await load() } }
            }
            Text("Withdrawing stops queued checks and prevents new submissions that need screening. It cannot recall content already sent for review.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: authentication.token) { await load() }
    }

    private func client(_ token: String) throws -> Client {
        try RepbaseAPIClientFactory.makeAuthenticated(
            serverURL: authentication.configuration.serverURL, token: token,
            allowInsecureLocalhost: authentication.configuration.allowsInsecureLocalhost)
    }

    private func load() async {
        granted = nil
        error = nil
        guard let token = authentication.token else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await AccountSafetyConsent.granted(client: client(token))
            guard !Task.isCancelled, authentication.token == token else { return }
            granted = result
        } catch {
            guard !Task.isCancelled, authentication.token == token else { return }
            self.error = "Could not load your safety-review preference. Please retry."
        }
    }

    private func update(withdraw: Bool) async {
        guard let token = authentication.token else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let api = try client(token)
            if withdraw { try await AccountSafetyConsent.set(false, client: api) }
            else { try await AccountSafetyConsent.set(true, client: api) }
            guard !Task.isCancelled, authentication.token == token else { return }
            granted = !withdraw
        } catch is ModerationConsent.NotGranted {
        } catch {
            guard !Task.isCancelled, authentication.token == token else { return }
            self.error = "Your preference could not be updated. Please retry."
        }
    }
}
