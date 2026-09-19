import Foundation
import ActivityKit
import AppIntents

nonisolated struct ActiveWorkoutWidgetState: Codable, Hashable, Sendable {
    static let filename = "active-workout-widget.json"
    var revision: String
    var sessionID: String
    var workout: String
    var exercise: String
    var setID: String
    var setNumber: Int
    var setCount: Int
    var weight: String
    var reps: String
    var startedAt: Date
    var updatedAt: Date
    var logged: Int
    var total: Int
    var busy: Bool
    var message: String?
    var finished: Bool { setID.isEmpty }
    var isFresh: Bool {
        let now = Date()
        return updatedAt <= now && startedAt <= now
            && now.timeIntervalSince(updatedAt) < 3600
            && now.timeIntervalSince(startedAt) < 8 * 3600
    }
    static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)?
            .appendingPathComponent(filename)
    }
    static func read() -> Self? {
        guard let file, let data = try? Data(contentsOf: file),
              let state = try? JSONDecoder().decode(Self.self, from: data), state.isFresh else { return nil }
        return state
    }
}

nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    typealias ContentState = ActiveWorkoutWidgetState
    var sessionID: String
}

/// LiveActivityIntent is executed in the app process, where the authenticated
/// store lives. No API token or write queue is copied into the extension.
@MainActor
enum WorkoutWidgetActionRouter {
    static var perform: ((String, String) async throws -> Void)?
}

nonisolated struct WorkoutWidgetAction: LiveActivityIntent {
    static var title: LocalizedStringResource = "Update active workout"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Revision") var revision: String
    @Parameter(title: "Action") var action: String
    init() {}
    init(revision: String, action: String) {
        self.revision = revision
        self.action = action
    }
    @MainActor
    func perform() async throws -> some IntentResult {
        guard let handler = WorkoutWidgetActionRouter.perform else {
            throw WorkoutWidgetActionError.openApp
        }
        try await handler(revision, action)
        return .result()
    }
}

nonisolated enum WorkoutWidgetActionError: LocalizedError {
    case openApp
    var errorDescription: String? { "Open Rytivo to restore your active workout, then try again." }
}
