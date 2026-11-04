import Foundation

/// These types cannot be passed to PlannerStore.save or completion methods.
/// Sharing is a limited projection, not ownership of another person's entry.
nonisolated struct CalendarSharePerson: Identifiable, Hashable, Sendable {
    let id: Int
    let username: String
    let displayName: String
    let profilePhotoURL: URL?

    var name: String { displayName.isEmpty ? username : displayName }
}

nonisolated enum CalendarShareScope: String, CaseIterable, Identifiable, Sendable {
    case occurrence, series
    var id: String { rawValue }
    var title: String {
        switch self {
        case .occurrence: String(localized: "Only this occurrence", bundle: .app, locale: .app)
        case .series: String(localized: "This and future occurrences", bundle: .app, locale: .app)
        }
    }
}

nonisolated struct SharedCalendarPlan: Identifiable, Hashable, Sendable {
    let id: String
    let shareID: Int
    let owner: CalendarSharePerson
    let kind: String
    let title: String
    let category: String
    let color: PlannerItemColor?
    let schedulingTimezone: String
    let date: String
    let time: String?
    let durationMinutes: Int?
    let isComplete: Bool
    let isRecurring: Bool
}

nonisolated struct CalendarShareInvitation: Identifiable, Hashable, Sendable {
    let id: Int
    let owner: CalendarSharePerson
    let recipient: CalendarSharePerson
    let scope: String
    let status: String
    let startsOn: String?
    let item: SharedCalendarPlan?
    var appliesToSelectedOccurrence: Bool? = nil
    var isPending: Bool { status == "pending" }
    var isActive: Bool { status == "pending" || status == "accepted" }
}

nonisolated struct SharedCalendarMonthDay: Sendable {
    let date: String
    let total: Int
    let items: [SharedCalendarPlan]
}

nonisolated struct CalendarFollowerPage: Sendable {
    let people: [CalendarSharePerson]
    let nextPage: Int?
}
