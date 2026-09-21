import SafariServices
import SwiftUI

/// The backend-hosted workspace shares the web app's authorization services.
/// It uses its own short-lived, CSRF-protected session; never put the app's
/// Keychain token into a URL, web script, or browser cookie.
struct AdministrationView: View {
    @Environment(AuthenticationStore.self) private var authentication

    private var workspaceURL: URL? {
        guard var components = URLComponents(
            url: authentication.configuration.serverURL,
            resolvingAgainstBaseURL: false
        ), components.scheme?.lowercased() == "https",
           components.host != nil,
           components.user == nil, components.password == nil else { return nil }
        components.path = "/access/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    var body: some View {
        if let workspaceURL {
            AdministrationBrowser(url: workspaceURL)
                .ignoresSafeArea(edges: .bottom)
        } else {
            ContentUnavailableView(
                "Secure connection required",
                systemImage: "lock.shield",
                description: Text("Administration is only available through your configured HTTPS server.")
            )
        }
    }
}

private struct AdministrationBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
