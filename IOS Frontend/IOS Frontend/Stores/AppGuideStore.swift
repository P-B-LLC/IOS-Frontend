//
//  AppGuideStore.swift
//  IOS Frontend
//
//  Whether the welcome guide is on screen, where in it somebody is, and
//  which tips this account has put away.
//
//  The server records that a tour was finished, so it opens by itself once
//  per account rather than once per install. This phone keeps its own note
//  as well: it means a launch after the first finish asks the server
//  nothing, and that a finish the server never heard about still counts.
//

import Foundation
import Observation

@Observable
@MainActor
final class AppGuideStore {
    /// The tour on screen, or nil when it is not.
    private(set) var progress: AppGuideProgress?
    private(set) var dismissedTips: Set<AppGuideTip> = []

    private struct Account {
        let id: Int
        let origin: String
    }

    private var configuration: APIConfiguration?
    private var token: String?
    private var account: Account?
    private var connectionGeneration = UUID()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isTouring: Bool { progress != nil }

    /// Signed in: load this account's tips, and open the tour if it is new.
    ///
    /// `justRegistered` is the account created in this app session. It is
    /// shown round even when the server cannot be asked -- an older server
    /// without the endpoint -- because it is new whatever the server says.
    func connect(
        configuration: APIConfiguration,
        token: String,
        accountID: Int,
        justRegistered: Bool
    ) async {
        let generation = UUID()
        connectionGeneration = generation
        self.configuration = configuration
        self.token = token
        let account = Account(id: accountID, origin: configuration.serverURL.absoluteString)
        self.account = account
        progress = nil
        dismissedTips = storedTips(for: account)

        let seenKey = AppGuide.seenKey(accountID: account.id, origin: account.origin)
        guard !defaults.bool(forKey: seenKey) else { return }
        let server: Bool?
        do {
            server = try await GuideAPIRepository(configuration: configuration, token: token).isCompleted()
        } catch {
            server = nil
        }
        guard connectionGeneration == generation,
              AppGuide.opensByItself(
                  server: server,
                  seenHere: defaults.bool(forKey: seenKey),
                  justRegistered: justRegistered
              )
        else { return }
        await open(generation: generation)
    }

    func disconnect() {
        connectionGeneration = UUID()
        configuration = nil
        token = nil
        account = nil
        progress = nil
        // The next person's tips are their own.
        dismissedTips = []
    }

    /// From Settings → Help, at any time.
    func start() async {
        await open(generation: connectionGeneration)
    }

    private func open(generation: UUID) async {
        guard progress == nil, let configuration, let token else { return }
        // A failed lookup leaves the step out rather than the tour.
        let moderate = (try? await ProfileAPIRepository(
            configuration: configuration, token: token
        ).canModerate()) ?? false
        guard connectionGeneration == generation, progress == nil else { return }
        progress = AppGuideProgress(steps: AppGuide.steps(for: AppGuideAccess(moderate: moderate)))
    }

    func next() { progress?.next() }
    func back() { progress?.back() }

    /// Finished, skipped or closed. All three mean asked once is enough, and
    /// Help has it after that.
    func finish() {
        progress = nil
        guard let account, let configuration, let token else { return }
        defaults.set(true, forKey: AppGuide.seenKey(accountID: account.id, origin: account.origin))
        // Not awaited: nothing on screen waits for it, and the note above
        // already keeps this phone from asking again if it fails.
        Task {
            try? await GuideAPIRepository(configuration: configuration, token: token).markCompleted()
        }
    }

    // MARK: - Tips

    func isDismissed(_ tip: AppGuideTip) -> Bool {
        dismissedTips.contains(tip)
    }

    func dismiss(_ tip: AppGuideTip) {
        dismissedTips.insert(tip)
        guard let account else { return }
        defaults.set(
            dismissedTips.map(\.rawValue).sorted(),
            forKey: AppGuide.tipsKey(accountID: account.id, origin: account.origin)
        )
    }

    func resetTips() {
        dismissedTips = []
        guard let account else { return }
        defaults.removeObject(forKey: AppGuide.tipsKey(accountID: account.id, origin: account.origin))
    }

    private func storedTips(for account: Account) -> Set<AppGuideTip> {
        let saved = defaults.stringArray(
            forKey: AppGuide.tipsKey(accountID: account.id, origin: account.origin)
        ) ?? []
        return Set(saved.compactMap(AppGuideTip.init(rawValue:)))
    }
}
