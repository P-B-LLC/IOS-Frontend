import SwiftUI
import SafariServices

/// Discoverability only. The session-authenticated dashboard checks grants again
/// on every page, preview and decision. App tokens never enter a URL or browser.
struct ModerationDashboardEntry: View {
    @Environment(AuthenticationStore.self) private var authentication
    @Environment(\.scenePhase) private var scenePhase
    @State private var allowed = false
    @State private var checking = true
    @State private var failed = false
    @State private var refreshID = UUID()
    @State private var showingDashboard = false

    var body: some View {
        Group {
            if allowed {
                Button {
                    showingDashboard = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Moderation dashboard").font(.headline)
                            Text("Review flagged posts and approve or reject them")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward").foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingDashboard) {
                    ModerationBrowser(url: authentication.configuration.serverURL
                        .appendingPathComponent("access/reports/")
                        .appending(queryItems: [URLQueryItem(name: "kind", value: "media")]))
                }
            } else if checking {
                ProgressView("Checking moderation access…")
                    .font(.footnote)
            } else if failed {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Couldn’t check moderation access", systemImage: "wifi.exclamationmark")
                        .font(.subheadline)
                    Text("Your dashboard has not been unlocked. Check your connection and retry.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Retry access check") { refreshID = UUID() }
                }
                .padding(16)
            }
        }
        .task(id: refreshID) {
            let attempt = refreshID
            allowed = false
            failed = false
            checking = true
            defer { if refreshID == attempt { checking = false } }
            guard let token = authentication.token else { return }
            do {
                let repository = try ProfileAPIRepository(configuration: authentication.configuration, token: token)
                let result = try await repository.canModerate()
                guard !Task.isCancelled, refreshID == attempt, authentication.token == token else { return }
                allowed = result
            } catch {
                guard !Task.isCancelled, refreshID == attempt, authentication.token == token else { return }
                allowed = false
                failed = true
            }
        }
        .onChange(of: authentication.token) { _, _ in
            allowed = false
            showingDashboard = false
            refreshID = UUID()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshID = UUID() }
        }
    }
}

private struct ModerationBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
