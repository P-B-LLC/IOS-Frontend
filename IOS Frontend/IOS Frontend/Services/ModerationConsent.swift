import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Permission is per submission, not device-wide or silently reused by another
/// account. Cancelling does not send the request or the content to the server.
@MainActor
enum ModerationConsent {
    /// The person was asked, and said no.
    ///
    /// Not a failure. They chose it, so the stores treat this like a
    /// cancellation and show nothing: an error alert immediately after
    /// somebody presses Cancel tells them what they already know, in the
    /// voice the app uses for things going wrong.
    struct NotGranted: LocalizedError {
        var errorDescription: String? { "Nothing was submitted." }
    }

    /// There was no way to put the question.
    ///
    /// Worth showing, because nothing the person did explains it and the
    /// submission really did not happen. Kept separate from `NotGranted` so
    /// that silencing a decline does not also silence a fault.
    struct CannotAsk: LocalizedError {
        var errorDescription: String? {
            "Nothing was submitted. Safety-review permission could not be requested — reopen the app and try again."
        }
    }

    /// How the question gets asked: `true` allowed, `false` declined, `nil`
    /// could not ask.
    ///
    /// A closure so the ordering below can be tested where there is no window
    /// to put a dialog in. The account-safety package compiles these sources
    /// for macOS without UIKit, and serialisation is exactly the sort of thing
    /// that looks obviously right and is not.
    static var askForPermission: () async -> Bool? = { await presentDialog() }

    /// The tail of the queue. Asks run one at a time.
    ///
    /// They used to refuse instead. A second submission arriving while a
    /// dialog was up hit an `isPresenting` guard and threw, so somebody was
    /// told nothing was submitted having never been asked — and the wording
    /// blamed the permission they were never offered. Posting a photo while a
    /// comment was still in flight was enough to do it.
    private static var lastAsk: Task<Void, Never> = Task {}

    static func require() async throws {
        try Task.checkCancellation()

        let predecessor = lastAsk
        let ask = Task { @MainActor () -> Bool? in
            // Wait for whoever is already asking, then ask. Queued rather
            // than refused, and in arrival order.
            await predecessor.value
            return await askForPermission()
        }
        lastAsk = Task { _ = await ask.value }

        let answer = await ask.value
        try Task.checkCancellation()
        guard let allowed = answer else { throw CannotAsk() }
        guard allowed else { throw NotGranted() }
    }

#if canImport(UIKit)
    private static func presentDialog() async -> Bool? {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !presenter.isBeingDismissed else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            let alert = UIAlertController(title: "Allow safety review?", message:
                "Rytivo sends the public-facing text and photos in this submission to OpenAI to check for harmful content. This can include profile names, bios, social handles, public gym details, comments, and titles or instructions in shared meals/workouts. Account credentials, private measurements, and unshared logs are excluded. Automated checks can make mistakes; contact \(LegalDocuments.contactEmail) to appeal. Allow this submission?",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "Allow and continue", style: .default) { _ in continuation.resume(returning: true) })
            presenter.present(alert, animated: true)
        }
    }
#else
    /// There is no window to ask in, so permission has not been given.
    ///
    /// `nil` rather than `false`, because "could not ask" is not "was asked
    /// and declined" — and a headless build must not become the one path that
    /// submits content nobody agreed to have reviewed.
    private static func presentDialog() async -> Bool? { nil }
#endif
}
