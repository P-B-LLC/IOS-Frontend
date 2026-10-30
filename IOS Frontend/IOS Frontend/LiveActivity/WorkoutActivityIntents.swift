//
//  WorkoutActivityIntents.swift
//  IOS Frontend
//
//  The buttons on the Lock Screen and in the Dynamic Island.
//
//  Compiled into both targets: the extension needs the types to draw a button,
//  and the app is where the system runs them -- a LiveActivityIntent's
//  perform() runs in the app's process, waking or launching it in the
//  background -- so the work itself is handed to the app through
//  `WorkoutActivityActionCenter`.
//

import AppIntents
import Foundation

nonisolated enum WorkoutActivityAction: Sendable, Equatable {
    case completeSet(sessionID: Int, exerciseID: UUID, setID: UUID)
    case toggleRest(sessionID: Int, restID: UUID)
    case skipRest(sessionID: Int, restID: UUID)
    case addRest(sessionID: Int, restID: UUID, seconds: Int)

    var sessionID: Int {
        switch self {
        case .completeSet(let id, _, _), .toggleRest(let id, _), .skipRest(let id, _), .addRest(let id, _, _):
            return id
        }
    }
}

/// Where the app takes delivery of a Lock Screen tap.
///
/// The app installs its handler at launch. In the extension nothing is ever
/// installed and nothing is ever performed there, which is the point: the
/// type only has to exist for the buttons to be drawn.
nonisolated final class WorkoutActivityActionCenter: @unchecked Sendable {
    static let shared = WorkoutActivityActionCenter()
    typealias Handler = @Sendable @MainActor (WorkoutActivityAction) async -> Void

    private let lock = NSLock()
    private var handler: Handler?

    func install(_ handler: @escaping Handler) {
        lock.withLock { self.handler = handler }
    }

    func perform(_ action: WorkoutActivityAction) async {
        guard let handler = lock.withLock({ self.handler }) else { return }
        await handler(action)
    }
}

struct CompleteWorkoutSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete set"
    static let description = IntentDescription("Logs the current set of your workout.")
    // Only meaningful from the Live Activity it was drawn on.
    static let isDiscoverable = false

    @Parameter(title: "Session") var sessionID: Int
    @Parameter(title: "Exercise") var exerciseID: String
    @Parameter(title: "Set") var setID: String

    init() {}

    init(sessionID: Int, exerciseID: String, setID: String) {
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.setID = setID
    }

    func perform() async throws -> some IntentResult {
        if let exercise = UUID(uuidString: exerciseID), let set = UUID(uuidString: setID) {
            await WorkoutActivityActionCenter.shared.perform(
                .completeSet(sessionID: sessionID, exerciseID: exercise, setID: set)
            )
        }
        return .result()
    }
}

struct ToggleRestTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or resume rest"
    static let description = IntentDescription("Pauses the rest timer, or resumes it.")
    static let isDiscoverable = false

    @Parameter(title: "Session") var sessionID: Int
    @Parameter(title: "Rest") var restID: String

    init() {}

    init(sessionID: Int, restID: String) {
        self.sessionID = sessionID
        self.restID = restID
    }

    func perform() async throws -> some IntentResult {
        if let rest = UUID(uuidString: restID) {
            await WorkoutActivityActionCenter.shared.perform(.toggleRest(sessionID: sessionID, restID: rest))
        }
        return .result()
    }
}

struct SkipRestTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip rest"
    static let description = IntentDescription("Ends the rest timer now.")
    static let isDiscoverable = false

    @Parameter(title: "Session") var sessionID: Int
    @Parameter(title: "Rest") var restID: String

    init() {}

    init(sessionID: Int, restID: String) {
        self.sessionID = sessionID
        self.restID = restID
    }

    func perform() async throws -> some IntentResult {
        if let rest = UUID(uuidString: restID) {
            await WorkoutActivityActionCenter.shared.perform(.skipRest(sessionID: sessionID, restID: rest))
        }
        return .result()
    }
}

struct AddRestTimeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add rest time"
    static let description = IntentDescription("Adds fifteen seconds to the rest timer.")
    static let isDiscoverable = false

    @Parameter(title: "Session") var sessionID: Int
    @Parameter(title: "Rest") var restID: String
    @Parameter(title: "Seconds") var seconds: Int

    init() {}

    init(sessionID: Int, restID: String, seconds: Int) {
        self.sessionID = sessionID
        self.restID = restID
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        if let rest = UUID(uuidString: restID) {
            await WorkoutActivityActionCenter.shared.perform(
                .addRest(sessionID: sessionID, restID: rest, seconds: seconds)
            )
        }
        return .result()
    }
}
