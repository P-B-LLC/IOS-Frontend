import SwiftUI

/// Planner-specific Figma tokens; shared typography and action colors stay in
/// the existing design system. Asset variants follow the app's appearance.
enum PlannerStyle {
    static let soft = Color("PlannerSoft")
    static let accentText = Color("PlannerAccentText")
    static let success = Color("PlannerSuccess")
    static let overdueCount = Color.repbaseDynamic(light: RepbaseDesign.danger, dark: Color(hex: 0xFF8FA0))
    static let radius: CGFloat = 28
}

extension View {
    func plannerSurface(padding: CGFloat = 16, soft: Bool = false) -> some View {
        modifier(PlannerSurfaceModifier(padding: padding, soft: soft))
    }
}

private struct PlannerSurfaceModifier: ViewModifier {
    @Environment(\.homeTimeOfDay) private var timeOfDay
    let padding: CGFloat
    let soft: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(soft ? PlannerStyle.soft : timeOfDay.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: PlannerStyle.radius))
            .overlay {
                RoundedRectangle(cornerRadius: PlannerStyle.radius)
                    .strokeBorder(soft ? Color.clear : timeOfDay.canvasBorder, lineWidth: 1)
            }
    }
}
