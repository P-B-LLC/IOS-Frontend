import Foundation
import Observation
import RepbaseAPI
import UIKit
import UserNotifications

@MainActor
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationCoordinator.shared.received(token: deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotificationCoordinator.shared.registrationFailed()
    }
}

/// One serialized registration writer. A newer preference always follows an
/// in-flight write, rather than racing it and restoring an older setting.
@Observable @MainActor
final class PushNotificationCoordinator {
    static let shared = PushNotificationCoordinator()
    private(set) var isSyncing = false
    private(set) var errorMessage: String?
    private(set) var routeID: UUID?
    private var pendingRouteOwner: Int?
    private var accountID: Int?
    private var client: Client?
    private var deviceToken: String?
    private var revision = UUID()
    private var worker: Task<Void, Never>?

    func connect(configuration: APIConfiguration, token: String, accountID: Int) {
        do {
            client = try RepbaseAPIClientFactory.makeAuthenticated(
                serverURL: configuration.serverURL, token: token,
                allowInsecureLocalhost: configuration.allowsInsecureLocalhost
            )
            self.accountID = accountID
            consumePendingRoute()
            refresh()
        } catch {
            errorMessage = "Community notifications could not connect. Try again."
        }
    }

    func disconnect() {
        // Server logout revokes the login token and cascades its device rows.
        // Do not cancel an in-flight write and start a competing writer.
        revision = UUID()
        client = nil
        accountID = nil
        pendingRouteOwner = nil
        routeID = nil
        errorMessage = nil
    }

    func refresh() {
        guard client != nil else { return }
        // APNs registration itself does not prompt for alert permission.
        // Register even after denial so the server can receive the opt-out.
        UIApplication.shared.registerForRemoteNotifications()
        synchronize()
    }

    func received(token: String) {
        deviceToken = token // Memory only; ask APNs again on each launch.
        synchronize()
    }

    func registrationFailed() {
        guard client != nil else { return }
        errorMessage = "This device could not register for community alerts. Check your connection and retry."
    }

    func synchronize() {
        revision = UUID()
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    private func drain() async {
        isSyncing = true
        defer { worker = nil; isSyncing = false }
        while let client, let deviceToken, accountID != nil {
            let run = revision
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard run == revision else { continue }
            let authorized = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
            let enabled = authorized && (UserDefaults.standard.object(forKey: "notifications.social") as? Bool ?? true)
            guard let raw = Bundle.main.object(forInfoDictionaryKey: "RytivoAPNsEnvironment") as? String,
                  let environment = Components.Schemas.EnvironmentEnum(rawValue: raw) else {
                errorMessage = "This build is missing its push notification environment."
                return
            }
            do {
                let response = try await client.registerPushDevice(body: .json(.init(
                    token: deviceToken, environment: environment, communityEnabled: enabled
                )))
                switch response {
                case .noContent: break
                case .undocumented:
                    throw PushRegistrationError.rejected
                }
                if run == revision { errorMessage = nil; return }
            } catch {
                if run == revision {
                    errorMessage = "Community alert settings haven't synced. Your previous setting may still apply. Retry when connected."
                    return
                }
            }
        }
    }

    func openCommunity(accountID: Int) {
        pendingRouteOwner = accountID
        consumePendingRoute()
    }

    private func consumePendingRoute() {
        guard let accountID, let pendingRouteOwner else { return }
        if pendingRouteOwner == accountID { routeID = UUID() }
        self.pendingRouteOwner = nil
    }

    func clearRoute() { routeID = nil }

    private enum PushRegistrationError: Error { case rejected }
}
