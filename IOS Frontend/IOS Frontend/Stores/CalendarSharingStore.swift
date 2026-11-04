import Foundation
import Observation

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
