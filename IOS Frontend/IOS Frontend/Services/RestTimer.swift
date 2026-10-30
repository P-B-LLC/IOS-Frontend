import Foundation

/// A rest between sets, kept as dates rather than as a ticking counter.
///
/// The previous approach is what made the timer unreliable: a counter only
/// advances while the app is running, so locking the phone or opening another
/// app stopped it, and returning picked up where it had frozen. An end date
/// keeps counting whatever the app is doing. The screen, the Lock Screen and
/// the notification all read the same date, so they cannot disagree, and the
/// value is part of the session checkpoint, so moving between exercises,
/// leaving the screen or relaunching never restarts it.
nonisolated struct RestTimer: Codable, Hashable, Sendable {
    enum Phase: String, Codable, Hashable, Sendable {
        case running
        case paused
        case finished
    }

    /// Identifies this countdown, so a notification or Lock Screen tap meant
    /// for an earlier rest cannot act on this one.
    let id: UUID
    /// The exercise whose set started the rest.
    let exerciseID: UUID?
    /// The length it was started with, which Reset returns to.
    let plannedSeconds: TimeInterval
    /// The length after any ±15 adjustments, which progress is drawn against.
    private(set) var totalSeconds: TimeInterval
    /// Set while it runs.
    private(set) var endsAt: Date?
    /// Set while it is paused: what was left at the moment of pausing.
    private(set) var pausedRemaining: TimeInterval?

    /// The longest rest the app offers. The backend caps an exercise's rest at
    /// an hour too, so nothing here can exceed what a plan could save.
    static let maximumSeconds: TimeInterval = 3600

    static func start(seconds: TimeInterval, exerciseID: UUID?, at now: Date = Date()) -> RestTimer {
        let length = min(max(seconds, 0), maximumSeconds)
        return RestTimer(
            id: UUID(),
            exerciseID: exerciseID,
            plannedSeconds: length,
            totalSeconds: length,
            endsAt: now.addingTimeInterval(length),
            pausedRemaining: nil
        )
    }

    func phase(at now: Date = Date()) -> Phase {
        if pausedRemaining != nil { return .paused }
        guard let endsAt, endsAt > now else { return .finished }
        return .running
    }

    func remaining(at now: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// When this countdown began, as the Lock Screen's progress bar needs it:
    /// the end less the full length, so the bar stays right after an
    /// adjustment without having stored a second start.
    var startedAt: Date? { endsAt.map { $0.addingTimeInterval(-totalSeconds) } }

    /// Fraction done, 0 to 1.
    func progress(at now: Date = Date()) -> Double {
        guard totalSeconds > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / totalSeconds))
    }

    mutating func pause(at now: Date = Date()) {
        guard phase(at: now) == .running else { return }
        pausedRemaining = remaining(at: now)
        endsAt = nil
    }

    mutating func resume(at now: Date = Date()) {
        guard let left = pausedRemaining else { return }
        pausedRemaining = nil
        endsAt = now.addingTimeInterval(left)
    }

    /// Adds or takes off time. A rest that runs out this way is finished
    /// rather than negative, and one that has already finished can be given
    /// more time, which starts it again from now.
    mutating func adjust(by seconds: TimeInterval, at now: Date = Date()) {
        let left = min(max(remaining(at: now) + seconds, 0), Self.maximumSeconds)
        totalSeconds = min(max(totalSeconds + seconds, left), Self.maximumSeconds)
        if pausedRemaining != nil {
            pausedRemaining = left
        } else {
            endsAt = now.addingTimeInterval(left)
        }
    }

    /// Starts the same rest again from its planned length.
    mutating func reset(at now: Date = Date()) {
        totalSeconds = plannedSeconds
        pausedRemaining = nil
        endsAt = now.addingTimeInterval(plannedSeconds)
    }

    /// "1:30", or "1:02:00" for a rest an hour long.
    static func clockText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The rest lengths the app offers to choose from, so every picker and the
/// Settings screen agree.
nonisolated enum RestDurationOptions {
    static let seconds: [Int] = [0, 15, 30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240, 300, 360, 420, 480, 600]
    /// What a new account starts with, before anybody chooses.
    static let standardDefault = 90

    /// "1:30", "45s" or "Off".
    static func label(_ seconds: Int) -> String {
        guard seconds > 0 else {
            return String(localized: "Off", bundle: .app, locale: .app, comment: "No rest timer after a set")
        }
        if seconds < 60 {
            return String(localized: "\(seconds)s", bundle: .app, locale: .app, comment: "A rest length in seconds, such as 45s")
        }
        return RestTimer.clockText(TimeInterval(seconds))
    }
}
