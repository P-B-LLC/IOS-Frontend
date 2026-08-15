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
        case .workout: return "dumbbell.fill"
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

/// One task or event on a day.
nonisolated struct PlannerEntry: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// The backend identifier. Nil only for a draft that has not been saved.
    var serverID: Int?
    var kind: PlannerKind
    var title: String
    var category: PlannerCategory
    /// Literal OAS `YYYY-MM-DD`.
    var date: String
    /// Literal OAS `HH:mm:ss`. Nil means the day is enough.
    var time: String?
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
        date: String,
        time: String? = nil,
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
        self.date = date
        self.time = time
        self.isComplete = isComplete
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.notes = notes
    }

    /// Only a task is ticked off. An event happens whether or not you attend.
    var isCompletable: Bool { kind == .task }

    /// The time shown beside the title, e.g. "16:00". Nil when untimed.
    var displayTime: String? {
        guard let time, time.count >= 5 else { return nil }
        return String(time.prefix(5))
    }
}
