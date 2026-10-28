import SwiftUI

extension View {
    /// Puts the language chosen in Settings into the environment.
    ///
    /// Applied once, at the root. Every `Text` built from a literal looks its
    /// string up in the environment's locale, so changing it here retranslates
    /// the whole app -- presentations included, since they inherit the
    /// environment of whatever presented them. The layout direction is set
    /// with it because SwiftUI only derives that from the launch language:
    /// switching to Arabic in Settings has to mirror the screen now, not at
    /// the next launch.
    func appLanguage() -> some View {
        modifier(AppLanguageEnvironment())
    }
}

private struct AppLanguageEnvironment: ViewModifier {
    func body(content: Content) -> some View {
        // Read in a body, so observation redraws this when the language changes.
        let localization = AppLocalization.shared
        content
            .environment(\.locale, localization.locale)
            .environment(
                \.layoutDirection,
                localization.language.isRightToLeft ? .rightToLeft : .leftToRight
            )
    }
}
