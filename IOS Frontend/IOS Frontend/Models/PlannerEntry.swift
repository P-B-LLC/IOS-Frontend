//
//  PlannerEntry.swift
//  IOS Frontend
//
//  Tasks and events on the planner.
//

import Foundation
import SwiftUI

/// What a planned item is for.
///
/// A short fixed list on purpose: the point of a category is to let a day be
/// read at a glance, which a free-text label would not do.
///
/// Tasks and events draw from different halves of it. A task is sorted by what
/// kind of doing it is, an event by what kind of occasion it is, and offering
/// "habit" while planning a holiday helps nobody. `other` is the one they share.
nonisolated enum PlannerCategory: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    // Tasks: kinds of doing.
    case habit
    case workout
    case errand
    case study
    case sleep
    case health
    case work
    case home

    // Events: kinds of occasion.
    case birthday
    case holiday
    case appointment
    case meeting
    case travel
    case social

    case other

    var id: String { rawValue }

    /// The categories a task may carry, in the order they are offered.
    static let forTask: [PlannerCategory] = [
        .habit, .workout, .errand, .study, .sleep, .health, .work, .home, .other,
    ]

    /// The categories an event may carry, in the order they are offered.
    static let forEvent: [PlannerCategory] = [
        .birthday, .holiday, .appointment, .meeting, .travel, .social, .other,
    ]

    static func available(for kind: PlannerKind) -> [PlannerCategory] {
        kind == .event ? forEvent : forTask
    }

    func suits(_ kind: PlannerKind) -> Bool {
        Self.available(for: kind).contains(self)
    }

    var title: String {
        switch self {
        case .habit: return "Habit"
        case .workout: return "Workout"
        case .errand: return "Errand"
        case .study: return "Study"
        case .sleep: return "Sleep"
        case .health: return "Health"
        case .work: return "Work"
        case .home: return "Home"
        case .birthday: return "Birthday"
        case .holiday: return "Holiday"
        case .appointment: return "Appointment"
        case .meeting: return "Meeting"
        case .travel: return "Travel"
        case .social: return "Social"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .habit: return "repeat"
        case .workout: return ActivityIconKind.lifting.systemName
        case .errand: return "bag.fill"
        case .study: return "book.fill"
        case .sleep: return "moon.fill"
        case .health: return "heart.fill"
        case .work: return "briefcase.fill"
        case .home: return "house.fill"
        case .birthday: return "gift.fill"
        case .holiday: return "sun.max.fill"
        case .appointment: return "calendar.badge.clock"
        case .meeting: return "person.2.fill"
        case .travel: return "airplane"
        case .social: return "bubble.left.and.bubble.right.fill"
        case .other: return "circle.fill"
        }
    }

    /// A distinct tint per category, so a day's list can be scanned by colour
    /// before it is read. Tasks and events share the list and the calendar
    /// dots, so the two halves have to stay distinguishable from each other
    /// as well as within themselves.
    var tint: Color {
        switch self {
        case .habit: return Color(hex: 0x8B7BD8)
        case .workout: return Color(hex: 0xE8622A)
        case .errand: return Color(hex: 0xE0913A)
        case .study: return Color(hex: 0x4E9CD8)
        case .sleep: return Color(hex: 0x6C6FA8)
        case .health: return Color(hex: 0xD8557A)
        case .work: return Color(hex: 0x4FA88B)
        case .home: return Color(hex: 0xB07C56)
        case .birthday: return Color(hex: 0xD94F9C)
        case .holiday: return Color(hex: 0xE2B33C)
        case .appointment: return Color(hex: 0x3E9FA8)
        case .meeting: return Color(hex: 0x5B7FD4)
        case .travel: return Color(hex: 0x2E8B57)
        case .social: return Color(hex: 0x8E44AD)
        case .other: return Color(hex: 0x8A8A8E)
        }
    }
}

/// Whether a planned item is finished, or simply happens.
nonisolated enum PlannerKind: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    /// Something to get done. Carries a checkbox.
    case task
    /// Something that happens at a time. Never completed.
    case event

    var id: String { rawValue }

    var title: String {
        switch self {
        case .task: return "Task"
        case .event: return "Event"
        }
    }
}

/// How much a planned item matters, next to the rest of its day.
///
/// Three levels rather than a flag, because "not urgent" is a real answer and
/// folding it into `normal` would make the two indistinguishable once a day
/// fills up. `normal` is the default: a priority nobody chose should not push
/// anything around.
nonisolated enum PlannerPriority: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case low
    case normal
    case high

    var id: String { rawValue }

    /// Offered strongest first. The picker exists to raise something; Normal is
    /// already what an item is without touching it.
    static let offered: [PlannerPriority] = [.high, .normal, .low]

    var title: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }

    /// The colour a called-out priority wears — the rose the app already uses
    /// for past due, because both mean the same thing to a reader: this one.
    var tint: Color { Color(hex: 0xD8557A) }

    /// Where this sits when a day is put in order. Lower comes first.
    ///
    /// Mirrors `PRIORITY_RANK` on the server, which is what actually orders
    /// the rows. Kept here because lists are merged and re-sorted on the
    /// client — Up Next stitches overdue items onto the chosen day, and the
    /// order the server sent does not survive that.
    var rank: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }

    /// What a row says about its priority, if anything.
    ///
    /// Only `high` speaks. A day where every row wore a badge would be a day
    /// with no emphasis in it, and `normal` is what most rows are.
    var badge: String? {
        self == .high ? "HIGH PRIORITY" : nil
    }

    var symbolName: String {
        switch self {
        case .low: return "arrow.down.circle"
        case .normal: return "minus.circle"
        case .high: return "exclamationmark.circle.fill"
        }
    }
}

/// The lengths a planned item may run for.
///
/// A namespace rather than an enum of cases: the value on the wire is a plain
/// count of minutes, and a closed set of cases would mean an entry saved on
/// another client with 37 minutes on it had nowhere to live.
nonisolated enum PlannerDuration {
    /// Matches `MIN_PLANNER_DURATION_MINUTES` / `MAX…` on the server, which is
    /// what actually refuses anything outside them.
    static let minimumMinutes = 5
    static let maximumMinutes = 1440

    /// What the picker offers. Short steps where people plan in short steps,
    /// coarser once a thing is long enough that ten minutes stops mattering.
    static let offered: [Int] = [15, 30, 45, 60, 90, 120, 180, 240, 360, 480]

    static func label(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, let m): return "\(m) min"
        case (let h, 0): return h == 1 ? "1 hour" : "\(h) hours"
        case (let h, let m): return "\(h) hr \(m) min"
        }
    }

    /// Minutes past midnight for a literal `HH:mm:ss`, or nil when there is
    /// no time to read.
    static func minutesPastMidnight(_ time: String?) -> Int? {
        guard let time, time.count >= 5,
              let hour = Int(time.prefix(2)),
              let minute = Int(time.dropFirst(3).prefix(2)) else { return nil }
        return hour * 60 + minute
    }
}

/// One task or event on a day.
nonisolated struct PlannerEntry: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// The backend identifier. Nil only for a draft that has not been saved.
    var serverID: Int?
    var kind: PlannerKind
    var title: String
    var category: PlannerCategory
    /// How much this matters next to the rest of its day. Sorts the day
    /// rather than decorating it.
    var priority: PlannerPriority
    /// Literal OAS `YYYY-MM-DD`.
    var date: String
    /// Literal OAS `HH:mm:ss`. Nil means the day is enough.
    var time: String?
    /// How long it runs, in minutes. Nil is the ordinary case: a reminder has
    /// a moment, not a length. Set, it is what the calendar blocks out.
    /// Never set without a `time` — the server refuses the pair.
    var durationMinutes: Int?
    var isComplete: Bool
    /// The workout this stands for, when the category is `workout`.
    var workoutID: Int?
    var workoutName: String?
    var notes: String

    init(
        id: UUID = UUID(),
        serverID: Int? = nil,
        kind: PlannerKind = .task,
        title: String,
        category: PlannerCategory = .other,
        priority: PlannerPriority = .normal,
        date: String,
        time: String? = nil,
        durationMinutes: Int? = nil,
        isComplete: Bool = false,
        workoutID: Int? = nil,
        workoutName: String? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.serverID = serverID
        self.kind = kind
        self.title = title
        self.category = category
        self.priority = priority
        self.date = date
        self.time = time
        self.durationMinutes = durationMinutes
        self.isComplete = isComplete
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.notes = notes
    }

    /// The server's copy of this entry, under the identity the app already
    /// knows it by.
    ///
    /// A saved entry comes back with a fresh local id, because the mapper
    /// builds one from the response and the response carries no local id.
    /// Dropping the old one in place therefore changed what the row was called
    /// halfway through an operation, and anything still holding the previous
    /// id — a list diffing its rows, a caller about to retire it — quietly
    /// stopped finding it.
    func identified(as id: UUID) -> PlannerEntry {
        PlannerEntry(
            id: id,
            serverID: serverID,
            kind: kind,
            title: title,
            category: category,
            priority: priority,
            date: date,
            time: time,
            durationMinutes: durationMinutes,
            isComplete: isComplete,
            workoutID: workoutID,
            workoutName: workoutName,
            notes: notes
        )
    }

    /// The day this sits on, as a date.
    ///
    /// The stored field is the server's `YYYY-MM-DD`, which is the right thing
    /// to send back but cannot be compared or formatted. Parsed by hand rather
    /// than through a formatter: this is a calendar day with no time and no
    /// zone, and handing it to one invites it to be shifted by the device's.
    var dayValue: Date? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }

    /// Whether two copies are the same entry.
    ///
    /// By server id, because the local one is not stable across reads. The
    /// overdue list and the month on screen are separate requests, and the
    /// mapper mints a fresh id for every row it builds, so one task arrives
    /// as two values with two different ids. Matching on those updated
    /// whichever list the change was made in and left the other showing the
    /// state before it — ticking a task off in Past due, then finding it
    /// unticked on its own day.
    ///
    /// Falls back to the local id for a draft that has never been saved,
    /// which is the only case where there is no server id to compare.
    func isSameEntry(as other: PlannerEntry) -> Bool {
        if let mine = serverID, let theirs = other.serverID {
            return mine == theirs
        }
        return id == other.id
    }

    /// Only a task is ticked off. An event happens whether or not you attend.
    var isCompletable: Bool { kind == .task }

    /// The time shown beside the title, e.g. "16:00". Nil when untimed.
    var displayTime: String? {
        guard let time, time.count >= 5 else { return nil }
        return String(time.prefix(5))
    }

    /// When it finishes, as `HH:mm`. Nil when nothing said how long.
    ///
    /// Wraps past midnight rather than stopping at it: a party that starts at
    /// 23:00 and runs two hours ends at 01:00, and saying 23:59 would be a lie
    /// about something the person entered themselves.
    var displayEndTime: String? {
        guard let durationMinutes,
              let start = PlannerDuration.minutesPastMidnight(time) else { return nil }
        let end = (start + durationMinutes) % (24 * 60)
        return String(format: "%02d:%02d", end / 60, end % 60)
    }

    /// "17:30 – 19:00" when a length is set, "17:30" when only a start is,
    /// nil when the day is all anyone said.
    var displayTimeRange: String? {
        guard let displayTime else { return nil }
        guard let displayEndTime else { return displayTime }
        return "\(displayTime) – \(displayEndTime)"
    }
}
