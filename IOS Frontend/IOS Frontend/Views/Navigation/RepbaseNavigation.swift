import SwiftUI

/// Somewhere the app can be sent from anywhere in it.
///
/// Home is a summary of four other areas, and every card on it offers to open
/// the one it summarises. Those offers used to be `NavigationLink`s, which
/// pushed the destination onto Home's own stack: you ended up reading the
/// workouts page with the bottom bar still lit on Home, and the way back was
/// a chevron rather than the bar. The bar was describing which tab you
/// started from rather than what you were looking at.
///
/// That is the arrangement `RepbaseRootView` was built to replace -- its own
/// note says pushing each area from home "meant the bar was only ever on
/// home" -- and the home cards simply never caught up.
nonisolated enum RepbaseDestination: Hashable {
    case workouts
    /// A specific day's workout, which the workouts tab cannot show on its
    /// own. Selects the tab and pushes the day onto it, so the bar reads
    /// Training and the chevron goes back to the week.
    case workoutDay(Weekday)
    case food
    case planner
    case social
    case account
}

/// Sends the app to `destination`, selecting the tab it lives on.
///
/// Injected by `RepbaseRootView`, which owns the tab selection. Defaults to
/// doing nothing so a view can be previewed outside the root without the
/// preview harness having to supply one.
struct RepbaseNavigateAction {
    var handler: (RepbaseDestination) -> Void = { _ in }

    func callAsFunction(_ destination: RepbaseDestination) {
        handler(destination)
    }
}

extension EnvironmentValues {
    @Entry var repbaseNavigate = RepbaseNavigateAction()
}
