import SwiftUI

// `RepbaseDestination` and the rules for where each case sends the app moved
// to RepbaseRoute.swift, which imports no SwiftUI and can therefore be tested.
// What is left here is the injection: the environment value, and the action
// that carries a destination to whoever owns the tab selection.

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
