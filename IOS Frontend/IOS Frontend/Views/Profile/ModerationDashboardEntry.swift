import SwiftUI
import SafariServices

/// Discoverability only. The session-authenticated dashboard checks grants again
/// on every page, preview and decision. App tokens never enter a URL or browser.
struct ModerationDashboardEntry: View {
    @Environment(AuthenticationStore.self) private var authentication
    @State private var allowed = false
    @State private var showingDashboard = false

    var body: some View {
        Group {
            if allowed {
                Button {
                    showingDashboard = true
                } label: {
                    Label("Moderation dashboard", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
                .sheet(isPresented: $showingDashboard) {
                    ModerationBrowser(url: authentication.configuration.serverURL
                        .appendingPathComponent("access/reports/")
                        .appending(queryItems: [URLQueryItem(name: "kind", value: "media")]))
                }
            }
        }
        .task(id: authentication.token) {
            allowed = false
            guard let token = authentication.token else { return }
            do {
                let repository = try ProfileAPIRepository(configuration: authentication.configuration, token: token)
                let result = try await repository.canModerate()
                guard !Task.isCancelled, authentication.token == token else { return }
                allowed = result
            } catch {
                allowed = false
            }
        }
        .onChange(of: authentication.token) { _, _ in showingDashboard = false }
    }
}

private struct ModerationBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
