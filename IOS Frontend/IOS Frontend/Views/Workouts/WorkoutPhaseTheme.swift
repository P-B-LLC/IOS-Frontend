//
//  WorkoutPhaseTheme.swift
//  IOS Frontend
//
//  Visual tokens for the prepare, focus, and recovery workout states.
//

import SwiftUI

enum WorkoutVisualPhase: Sendable, Equatable {
    case prepare
    case focus
    case recover

    // Workout state controls content, never colour. Every token below is a
    // dynamic colour and resolves against the trait when it is drawn, so none
    // of them consults which case this is.

    var canvasStart: Color { Color(uiColor: .systemBackground) }

    var canvasEnd: Color { Color(uiColor: .systemBackground) }

    var canvasMiddle: Color { Color(uiColor: .systemBackground) }

    var accent: Color { RepbasePalette.caramel }

    var primaryText: Color { Color.primary }

    var secondaryText: Color { Color.secondary }

    var surfaceStart: Color { .repbaseDynamic(light: Color.white, dark: Color(hex: 0x252220)) }

    var surfaceEnd: Color { .repbaseDynamic(light: Color.white, dark: Color(hex: 0x252220)) }

    var heroStart: Color {
        .repbaseDynamic(light: RepbasePalette.oatmeal, dark: Color(hex: 0x2C2927))
    }

    var heroEnd: Color { .repbaseDynamic(light: Color.white, dark: Color(hex: 0x252220)) }

    /// Text drawn on a hero card.
    ///
    /// The hero learned light mode -- oatmeal through white -- while what is
    /// drawn on it kept the colours it had when the card was always dark:
    /// #D1D1D1 sand, pale mint, and plain white. On a light hero those are
    /// white on white, which is how a finished workout came to show a card
    /// with nothing readable on it.
    var onHeroPrimary: Color {
        .repbaseDynamic(light: RepbasePalette.espresso, dark: Color.white)
    }

    var onHeroSecondary: Color {
        .repbaseDynamic(
            light: RepbasePalette.espresso.opacity(0.66),
            dark: Color(hex: 0xB7DCCB)
        )
    }

    var onHeroDivider: Color {
        .repbaseDynamic(
            light: RepbasePalette.espresso.opacity(0.18),
            dark: Color(hex: 0x648474)
        )
    }

    /// The hairline on a card, and the one on a control.
    var cardBorder: Color {
        .repbaseDynamic(
            light: RepbasePalette.espresso.opacity(0.12),
            dark: Color.white.opacity(0.10)
        )
    }

    var controlBorder: Color {
        .repbaseDynamic(
            light: RepbasePalette.espresso.opacity(0.08),
            dark: Color.white.opacity(0.09)
        )
    }

    var onAccent: Color { Color.white }

    var primaryActionSurface: Color {
        .repbaseDynamic(light: RepbasePalette.charcoal, dark: Color.white)
    }

    var onPrimaryAction: Color {
        .repbaseDynamic(light: Color.white, dark: RepbasePalette.ink)
    }

    var shadow: Color {
        .repbaseDynamic(
            light: RepbasePalette.espresso.opacity(0.14),
            dark: Color.black.opacity(0.26)
        )
    }

}

private struct WorkoutVisualPhaseKey: EnvironmentKey {
    static let defaultValue: WorkoutVisualPhase = .prepare
}

extension EnvironmentValues {
    var workoutVisualPhase: WorkoutVisualPhase {
        get { self[WorkoutVisualPhaseKey.self] }
        set { self[WorkoutVisualPhaseKey.self] = newValue }
    }
}

struct WorkoutPhaseBackground: View {
    let phase: WorkoutVisualPhase

    var body: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: phase.canvasStart, location: 0),
                .init(color: phase.canvasMiddle, location: 0.56),
                .init(color: phase.canvasEnd, location: 1)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct WorkoutHeroBackground: View {
    let phase: WorkoutVisualPhase

    var body: some View {
        LinearGradient(
            colors: [phase.heroStart, phase.heroEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .bottomLeading) {
            RadialGradient(
                colors: [phase.accent.opacity(0.36), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 220
            )
        }
    }
}

private struct RepbaseScreenModifier: ViewModifier {
    let phase: WorkoutVisualPhase

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .foregroundStyle(phase.primaryText)
            .background { WorkoutPhaseBackground(phase: phase) }
            .workoutVisualPhase(phase)
            .tint(phase.accent)
    }
}

private struct RepbaseCardModifier: ViewModifier {
    @Environment(\.workoutVisualPhase) private var phase
    let contentPadding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(contentPadding)
            .foregroundStyle(phase.primaryText)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(phase.surfaceStart)
                    .shadow(
                        color: phase.shadow.opacity(0.32),
                        radius: 5,
                        x: 0,
                        y: 3
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(phase.cardBorder, lineWidth: 1)

            }
    }
}

private struct RepbaseControlSurfaceModifier: ViewModifier {
    @Environment(\.workoutVisualPhase) private var phase
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(phase.surfaceStart)
                    .shadow(color: phase.shadow.opacity(0.28), radius: 3, x: 0, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(phase.controlBorder, lineWidth: 0.75)

            }
    }
}

struct WorkoutPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let phase: WorkoutVisualPhase

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.community(.headline))
            .foregroundStyle(phase.onPrimaryAction)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(phase.primaryActionSurface)
                    .shadow(color: phase.shadow, radius: 9, x: 0, y: 5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension View {
    func workoutCard() -> some View {
        repbaseCard(contentPadding: 16, cornerRadius: RepbaseDesign.cardRadius)
    }

    func repbaseCard(contentPadding: CGFloat = 12, cornerRadius: CGFloat = RepbaseDesign.cardRadius) -> some View {
        modifier(
            RepbaseCardModifier(
                contentPadding: contentPadding,
                cornerRadius: cornerRadius
            )
        )
    }

    func repbaseScreen(_ phase: WorkoutVisualPhase) -> some View {
        modifier(RepbaseScreenModifier(phase: phase))
    }

    func repbaseControlSurface(cornerRadius: CGFloat = RepbaseDesign.controlRadius) -> some View {
        modifier(RepbaseControlSurfaceModifier(cornerRadius: cornerRadius))
    }

    func workoutVisualPhase(_ phase: WorkoutVisualPhase) -> some View {
        environment(\.workoutVisualPhase, phase)
    }
}

extension Color {
    /// A colour that resolves when it is drawn rather than when the body that
    /// mentions it is evaluated.
    ///
    /// This is the difference between the system colours following the app's
    /// appearance switch and ours not. `Color.primary` is backed by a dynamic
    /// UIColor, so flipping the trait repaints it with no view having to
    /// re-render. A token written as `isDark ? .black : .white` picks its side
    /// once, while a body happens to be running, and then keeps that answer
    /// until something re-runs the body -- which nothing does, because nothing
    /// declares a dependency on a preference read out of UserDefaults through
    /// a static. That is why the canvas turned black on switching and the
    /// cards on it stayed white, taking their white text with them.
    ///
    /// Written this way a token is simply correct at every moment, and no
    /// invalidation has to be arranged for it.
    static func repbaseDynamic(light: Color, dark: Color) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(dark)
                    : UIColor(light)
            }
        )
    }

    static func repbaseDynamic(light: UInt32, dark: UInt32) -> Color {
        repbaseDynamic(light: Color(hex: light), dark: Color(hex: dark))
    }

    init(hex: UInt32, alpha: Double = 1) {

        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
