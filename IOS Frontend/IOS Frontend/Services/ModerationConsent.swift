import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Permission is per submission, not device-wide or silently reused by another
/// account. Cancelling does not send the request or the content to the server.
@MainActor
enum ModerationConsent {
    struct NotGranted: LocalizedError {
        var errorDescription: String? { "Nothing was submitted. Safety-review permission is required to publish this content." }
    }

#if canImport(UIKit)
    private static var isPresenting = false

    static func require() async throws {
        try Task.checkCancellation()
        guard !isPresenting,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            throw NotGranted()
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !presenter.isBeingDismissed else { throw NotGranted() }
        isPresenting = true
        defer { isPresenting = false }
        let allowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let alert = UIAlertController(title: "Allow safety review?", message:
                "Rytivo sends the public-facing text and photos in this submission to OpenAI to check for harmful content. This can include profile names, bios, social handles, public gym details, comments, and titles or instructions in shared meals/workouts. Account credentials, private measurements, and unshared logs are excluded. Automated checks can make mistakes; contact \(LegalDocuments.contactEmail) to appeal. Allow this submission?",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "Allow and continue", style: .default) { _ in continuation.resume(returning: true) })
            presenter.present(alert, animated: true)
        }
        try Task.checkCancellation()
        guard allowed else { throw NotGranted() }
    }
#else
    /// There is no window to ask in, so permission has not been given.
    ///
    /// The account-safety package compiles these sources for macOS, without
    /// UIKit, and it copies AuthenticationStore -- which now asks for consent
    /// before registering. Refusing is the only honest answer when there is no
    /// way to put the question: a headless build must not become the one path
    /// that submits content nobody agreed to have reviewed. Nothing in that
    /// package registers an account, so this is a compile path rather than
    /// behaviour anything relies on.
    static func require() async throws { throw NotGranted() }
#endif
}
