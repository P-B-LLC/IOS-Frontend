import Foundation
import Observation
import RepbaseAPI

private enum CalendarSharingFailure: Error {
    case notConnected
}

/// Display-only sharing state. Never feeds PlannerStore, Home goals or reminders.
@Observable @MainActor
final class CalendarSharingStore {
    private var repository: CalendarSharingAPIRepository?
    private var generation = UUID()
    private var readID = UUID()
    private var lastMonth = Date()
    private var lastDay = Date()
    private(set) var connectionRevision = UUID()
    private(set) var lastLoadedDay: String?
    var isConnected: Bool { repository != nil }
    private(set) var monthDays: [SharedCalendarMonthDay] = []
    private(set) var dayItems: [SharedCalendarPlan] = []
    private(set) var invitations: [CalendarShareInvitation] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var isSupported = false
    private(set) var isSaving = false
    private(set) var people: [CalendarSharePerson] = []
    var showsOwn = true
    var hiddenOwnerIDs: Set<Int> = []

    var pendingInvitations: [CalendarShareInvitation] { invitations.filter(\.isPending) }
    func isVisible(_ ownerID: Int) -> Bool { !hiddenOwnerIDs.contains(ownerID) }
    func toggle(_ ownerID: Int) {
        if hiddenOwnerIDs.contains(ownerID) { hiddenOwnerIDs.remove(ownerID) }
        else { hiddenOwnerIDs.insert(ownerID) }
    }

    func connect(configuration: APIConfiguration, token: String) {
        disconnect()
        do { repository = try CalendarSharingAPIRepository(configuration: configuration, token: token) }
        catch { errorMessage = error.userFacingMessage }
    }

    func disconnect() {
        generation = UUID(); readID = UUID(); repository = nil
        connectionRevision = UUID()
        monthDays = []; dayItems = []; invitations = []; people = []
        errorMessage = nil; isLoading = false; isSaving = false; isSupported = false
        hiddenOwnerIDs = []; showsOwn = true
        lastLoadedDay = nil
    }

    func refresh(month: Date, day: Date) async {
        lastMonth = month; lastDay = day
        guard let repository else { return }
        let account = generation, request = UUID()
        readID = request
        isLoading = true; errorMessage = nil
        // Re-check permissions on each refresh instead of presenting stale grants.
        monthDays = []; dayItems = []; invitations = []
        defer { if account == generation, request == readID { isLoading = false } }
        let range = Self.monthWindow(month)
        do {
            let eligibleOwners = try await repository.people()
            guard account == generation, request == readID, !Task.isCancelled else { return }
            people = eligibleOwners
            let visible = eligibleOwners.filter { isVisible($0.id) }.map(\.id)
            async let monthResult = repository.month(start: range.start, end: range.end, ownerIDs: visible)
            async let dayResult = repository.day(date: PlannerStore.dateString(day), ownerIDs: visible)
            async let inviteResult = repository.invitations()
            let values = try await (monthResult, dayResult, inviteResult)
            guard account == generation, request == readID, !Task.isCancelled else { return }
            monthDays = values.0; dayItems = values.1; invitations = values.2
            lastLoadedDay = PlannerStore.dateString(day)
            isSupported = true
        } catch {
            guard account == generation, request == readID, !Task.isCancelled else { return }
            lastLoadedDay = PlannerStore.dateString(day)
            if let failure = error as? RepbaseAPIHTTPError, failure.statusCode == 404 {
                isSupported = false
                errorMessage = String(localized: "Calendar sharing needs the updated backend.", bundle: .app, locale: .app)
            } else { errorMessage = error.userFacingMessage }
        }
    }

    func followers(search: String, page: Int? = nil) async throws -> CalendarFollowerPage {
        guard let repository else { throw CalendarSharingFailure.notConnected }
        let account = generation
        let result = try await repository.followers(search: search, page: page)
        guard account == generation, !Task.isCancelled else { throw CancellationError() }
        return result
    }

    func refreshCurrent() async { await refresh(month: lastMonth, day: lastDay) }

    func sent(for entryID: Int) async throws -> [CalendarShareInvitation] {
        guard let repository else { throw CalendarSharingFailure.notConnected }
        let account = generation
        let values = try await repository.sent(entryID: entryID)
        guard account == generation, !Task.isCancelled else { throw CancellationError() }
        isSupported = true
        return values
    }

    func invite(entryID: Int, recipients: [Int], scope: CalendarShareScope, reinvite: Bool = false) async throws {
        guard let repository else { throw CalendarSharingFailure.notConnected }
        let account = generation
        try await repository.invite(entryID: entryID, recipients: recipients, scope: scope, reinvite: reinvite)
        guard account == generation, !Task.isCancelled else { throw CancellationError() }
    }

    func respond(_ invitation: CalendarShareInvitation, accept: Bool) async {
        guard let repository, !isSaving else { return }
        let account = generation
        isSaving = true; errorMessage = nil
        defer { if account == generation { isSaving = false } }
        do {
            try await repository.respond(id: invitation.id, accept: accept)
            guard account == generation, !Task.isCancelled else { return }
            invitations.removeAll { $0.id == invitation.id }
            await refresh(month: lastMonth, day: lastDay)
        } catch {
            guard account == generation, !Task.isCancelled else { return }
            errorMessage = error.userFacingMessage
        }
    }

    func revoke(_ shareID: Int) async throws {
        guard let repository else { throw CalendarSharingFailure.notConnected }
        let account = generation
        try await repository.revoke(id: shareID)
        guard account == generation, !Task.isCancelled else { throw CancellationError() }
    }

    func makePrivate(entryID: Int, scope: CalendarShareScope) async throws {
        guard let repository else { throw CalendarSharingFailure.notConnected }
        let account = generation
        try await repository.makePrivate(entryID: entryID, scope: scope)
        guard account == generation, !Task.isCancelled else { throw CancellationError() }
    }

    private static func monthWindow(_ date: Date) -> (start: String, end: String) {
        let calendar = Calendar.current
        let first = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let start = calendar.dateInterval(of: .weekOfYear, for: first)?.start ?? first
        let end = calendar.date(byAdding: .day, value: 41, to: start) ?? start
        return (PlannerStore.dateString(start), PlannerStore.dateString(end))
    }
}

#if DEBUG
extension CalendarSharingStore {
    /// Illustrative people and limited projections for native screenshot QA.
    /// No repository, credentials, photos, private planner fields or persistence
    /// are attached. Refresh/respond return at their existing repository guard.
    static var preview: CalendarSharingStore {
        let store = CalendarSharingStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = PlannerStore.dateString(today)
        let viewer = CalendarSharePerson(id: 900, username: "preview_you",
            displayName: "Alex Morgan", profilePhotoURL: nil)
        let maya = CalendarSharePerson(id: 901, username: "preview_maya",
            displayName: "Maya Chen", profilePhotoURL: nil)
        let jordan = CalendarSharePerson(id: 902, username: "preview_jordan",
            displayName: "Jordan Lee", profilePhotoURL: nil)
        let elena = CalendarSharePerson(id: 903, username: "preview_elena",
            displayName: "Elena Rivera", profilePhotoURL: nil)

        func plan(owner: CalendarSharePerson, on date: Date, title: String, time: String,
                  color: PlannerItemColor, complete: Bool = false) -> SharedCalendarPlan {
            let key = PlannerStore.dateString(date)
            return SharedCalendarPlan(id: "preview:\(owner.id):\(key)", shareID: owner.id,
                owner: owner, kind: "event", title: title, category: "health", color: color,
                schedulingTimezone: "America/Chicago", date: key, time: time,
                durationMinutes: 45, isComplete: complete, isRecurring: true)
        }

        let mayaToday = plan(owner: maya, on: today, title: "Easy run", time: "11:00:00", color: .lavender)
        let jordanToday = plan(owner: jordan, on: today, title: "Swim", time: "12:00:00", color: .teal)
        var monthDays: [SharedCalendarMonthDay] = []
        if let month = calendar.dateInterval(of: .month, for: today),
           let count = calendar.range(of: .day, in: .month, for: today)?.count {
            for offset in 0..<count {
                guard let date = calendar.date(byAdding: .day, value: offset, to: month.start) else { continue }
                let key = PlannerStore.dateString(date)
                if key == day {
                    monthDays.append(SharedCalendarMonthDay(date: key, total: 2, items: [mayaToday, jordanToday]))
                } else if calendar.component(.day, from: date).isMultiple(of: 3) {
                    let item = plan(owner: maya, on: date, title: "Easy run", time: "11:00:00", color: .lavender)
                    monthDays.append(SharedCalendarMonthDay(date: key, total: 1, items: [item]))
                } else if calendar.component(.day, from: date).isMultiple(of: 5) {
                    let item = plan(owner: jordan, on: date, title: "Swim", time: "12:00:00", color: .teal)
                    monthDays.append(SharedCalendarMonthDay(date: key, total: 1, items: [item]))
                }
            }
        }
        let invitationDay = calendar.date(byAdding: .day, value: 3, to: today) ?? today
        let proposed = plan(owner: elena, on: invitationDay, title: "Weekend hike",
                            time: "09:00:00", color: .sage)
        store.people = [maya, jordan]
        store.monthDays = monthDays
        store.dayItems = [mayaToday, jordanToday]
        store.invitations = [CalendarShareInvitation(id: 904, owner: elena, recipient: viewer,
            scope: "occurrence", status: "pending", startsOn: proposed.date, item: proposed)]
        store.lastMonth = today
        store.lastDay = today
        store.lastLoadedDay = day
        store.isSupported = true
        return store
    }
}
#endif
