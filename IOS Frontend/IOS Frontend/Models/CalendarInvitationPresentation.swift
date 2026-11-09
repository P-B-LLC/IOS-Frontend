import Foundation

/// A missing or refreshing response is not proof that there are no invitations.
/// This is display-only state; it never changes a grant or responds to a request.
enum CalendarInvitationPresentation: Equatable {
    case pending(Int)
    case loading
    case unavailable
    case empty

    init(pendingCount: Int, isLoading: Bool, hasError: Bool, isSupported: Bool) {
        if pendingCount > 0 { self = .pending(pendingCount) }
        else if isLoading { self = .loading }
        else if hasError || !isSupported { self = .unavailable }
        else { self = .empty }
    }

    var pendingCount: Int? {
        if case .pending(let count) = self { return count }
        return nil
    }
}
