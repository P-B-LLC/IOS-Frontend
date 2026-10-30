import Foundation
import SwiftUI
import RepbaseAPI

/// Appears once after sign-in for each policy version, never over the composer.
struct AccountAgreementGate<Content: View>: View {
    @Environment(AuthenticationStore.self) private var authentication
    private let content: () -> Content
    @State private var accepted = false
    @State private var checked = false
    @State private var busy = true
    @State private var error: String?
    @State private var document: LegalDocument?
    private let version = "2026-10-17"

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Group {
            if accepted { content() }
            else {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your Rytivo agreements").font(.title2.bold())
                    Text("Please review and accept our updated Privacy Policy and agreements to continue.")
                    ForEach(LegalDocuments.all) { item in
                        Button(item.title) { document = item }
                    }
                    if busy { ProgressView() }
                    if let error {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { Task { await load() } }.disabled(busy)
                    }
                    Toggle("I agree to the Privacy Policy and agreements", isOn: $checked)
                        .disabled(busy || error != nil)
                    Button("Agree and continue") { Task { await accept() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!checked || busy || error != nil)
                    Button("Sign out") { Task { await authentication.signOut() } }
                        .disabled(busy)
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
        .sheet(item: $document) { item in
            NavigationStack { LegalDocumentView(document: item) }
        }
    }

    private func client(_ token: String) throws -> Client {
        try RepbaseAPIClientFactory.makeAuthenticated(serverURL: authentication.configuration.serverURL,
            token: token, allowInsecureLocalhost: authentication.configuration.allowsInsecureLocalhost)
    }

    private func load() async {
        guard let token = authentication.token else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let output = try await client(token).accountAgreementRetrieve()
            guard !Task.isCancelled, authentication.token == token else { return }
            switch output {
            case .ok(let response):
                let result = try response.body.json
                guard result.version == version else { throw APIServiceError.malformedResponse }
                accepted = result.accepted
            case .undocumented(let status, _): throw APIServiceError.undocumentedStatus(status)
            }
        } catch {
            guard !Task.isCancelled, authentication.token == token else { return }
            self.error = String(
                localized: "Could not load the current agreements. Check your connection or update the app, then retry.",
                bundle: .app,
                locale: .app
            )
        }
    }

    private func accept() async {
        guard checked, let token = authentication.token else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let output = try await client(token).accountAgreementUpdate(body: .json(.init(version: version, accepted: true)))
            guard !Task.isCancelled, authentication.token == token else { return }
            switch output {
            case .ok(let response):
                let result = try response.body.json
                guard result.version == version, result.accepted else { throw APIServiceError.malformedResponse }
                accepted = true
            case .undocumented(let status, _): throw APIServiceError.undocumentedStatus(status)
            }
        } catch {
            guard !Task.isCancelled, authentication.token == token else { return }
            self.error = String(localized: "Your agreement could not be saved. Please retry.", bundle: .app, locale: .app)
        }
    }
}
