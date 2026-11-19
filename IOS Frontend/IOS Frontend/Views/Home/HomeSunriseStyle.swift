import SwiftUI

/// Approved Sunrise colors, shared by the five reviewed main pages.
/// Asset variants resolve with the existing appearance preference.
enum HomeSunriseStyle {
    static let backdrop = Color("SunriseBackdrop")
    static let heroTint = Color("SunriseHeroTint")

    static var backdropGradient: LinearGradient {
        LinearGradient(colors: [backdrop, heroTint], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct HomeSunriseGlow: View {
    var body: some View {
        // Exact 160 × 160 light/dark exports from the approved Figma layer.
        Image("HomeSunriseGlow")
            .renderingMode(.original)
            .frame(width: 160, height: 160)
            // SwiftUI mirrors horizontal offsets in a right-to-left layout.
            // Together with topTrailing alignment this stays off the edge.
            .offset(x: 48)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct HomeSunriseWeekBackground: View {
    var body: some View {
        RepbaseTactileCardBackground(cornerRadius: 24, tint: HomeSunriseStyle.heroTint)
    }
}
