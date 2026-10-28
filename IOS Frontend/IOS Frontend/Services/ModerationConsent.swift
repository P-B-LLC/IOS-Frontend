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
        var errorDescription: String? { String(localized: "Nothing was submitted.", bundle: .app, locale: .app) }
    }

    /// There was no way to put the question.
    ///
    /// Worth showing, because nothing the person did explains it and the
    /// submission really did not happen. Kept separate from `NotGranted` so
    /// that silencing a decline does not also silence a fault.
    struct CannotAsk: LocalizedError {
        var errorDescription: String? {
            String(
                localized: "Nothing was submitted. Safety-review permission could not be requested — reopen the app and try again.",
                bundle: .app,
                locale: .app
            )
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
    static var askForAccountPermission: () async -> Bool? = { await presentDialog(persistent: true) }

    /// The tail of the queue. Asks run one at a time.
    ///
    /// They used to refuse instead. A second submission arriving while a
    /// dialog was up hit an `isPresenting` guard and threw, so somebody was
    /// told nothing was submitted having never been asked — and the wording
    /// blamed the permission they were never offered. Posting a photo while a
    /// comment was still in flight was enough to do it.
    private static var lastAsk: Task<Void, Never> = Task {}

    /// Read the server each time: another device can withdraw this permission.
    /// The queue includes reading and saving, so concurrent posts ask only once.
    static func requireAccount(
        read: @escaping @MainActor () async throws -> Bool,
        save: @escaping @MainActor () async throws -> Void
    ) async throws {
        try Task.checkCancellation()
        let predecessor = lastAsk
        let operation = Task { @MainActor in
            await predecessor.value
            try Task.checkCancellation()
            if try await read() { return }
            guard let answer = await askForAccountPermission() else { throw CannotAsk() }
            guard answer else { throw NotGranted() }
            try Task.checkCancellation()
            try await save()
        }
        lastAsk = Task { _ = try? await operation.value }
        try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
        try Task.checkCancellation()
    }

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
    private static func presentDialog(persistent: Bool = false) async -> Bool? {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !presenter.isBeingDismissed else { return nil }

        // The disclosure and the closing question are separate whole sentences,
        // each translated on its own, so joining them builds no phrase.
        let disclosure = String(
            localized: "Rytivo sends the public-facing text, photos, and extracted video frames you submit to OpenAI for safety checks. This can include profile names, bios, social handles, public gym details, comments, and titles or instructions in shared meals/workouts. Audio, account credentials, private measurements, and unshared logs are excluded. Media stays unpublished while checks or moderator review are pending. Automated checks can make mistakes; contact \(LegalDocuments.contactEmail) to appeal.",
            bundle: .app,
            locale: .app
        )
        let question = persistent
            ? String(
                localized: "Allow safety review for this account? Your choice is saved; you can withdraw it in Settings under Safety review.",
                bundle: .app,
                locale: .app
            )
            : String(localized: "Allow this submission?", bundle: .app, locale: .app)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            let alert = UIAlertController(title: String(localized: "Allow safety review?", bundle: .app, locale: .app), message:
                disclosure + " " + question,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "Cancel", bundle: .app, locale: .app), style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: String(localized: "Allow and continue", bundle: .app, locale: .app), style: .default) { _ in continuation.resume(returning: true) })
            presenter.present(alert, animated: true)
        }
    }
#else
    /// There is no window to ask in, so permission has not been given.
    ///
    /// `nil` rather than `false`, because "could not ask" is not "was asked
    /// and declined" — and a headless build must not become the one path that
    /// submits content nobody agreed to have reviewed.
    private static func presentDialog(persistent: Bool = false) async -> Bool? { nil }
#endif
}
