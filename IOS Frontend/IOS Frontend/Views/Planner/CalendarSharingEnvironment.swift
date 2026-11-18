import SwiftUI

private struct CalendarSharingEnvironmentKey: EnvironmentKey {
    static let defaultValue: CalendarSharingStore? = nil
}

extension EnvironmentValues {
    /// Optional so standalone editors and old preview fixtures remain usable.
    var calendarSharing: CalendarSharingStore? {
        get { self[CalendarSharingEnvironmentKey.self] }
        set { self[CalendarSharingEnvironmentKey.self] = newValue }
    }
}
