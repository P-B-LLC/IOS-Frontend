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

    /// Workout state still controls content, but no longer controls color.
    /// Every token below follows the saved app appearance instead.
    private var isDark: Bool { RepbaseAppearancePreference.current == .dark }

    var canvasStart: Color { Color(uiColor: .systemBackground) }

    var canvasEnd: Color { Color(uiColor: .systemBackground) }

    var canvasMiddle: Color { Color(uiColor: .systemBackground) }

    var accent: Color { RepbasePalette.caramel }

    var primaryText: Color { Color.primary }

    var secondaryText: Color { Color.secondary }

    var surfaceStart: Color { isDark ? Color(hex: 0x252220) : Color.white }

    var surfaceEnd: Color { isDark ? Color(hex: 0x252220) : Color.white }

    var heroStart: Color { isDark ? Color(hex: 0x2C2927) : RepbasePalette.oatmeal }

    var heroEnd: Color { isDark ? Color(hex: 0x252220) : Color.white }

    var onAccent: Color { Color.white }

    var primaryActionSurface: Color {
        isDark ? Color.white : RepbasePalette.charcoal
    }

    var onPrimaryAction: Color {
        isDark ? RepbasePalette.ink : Color.white
    }

    var shadow: Color { isDark ? Color.black.opacity(0.26) : RepbasePalette.espresso.opacity(0.14) }

    var usesDarkAppearance: Bool { isDark }
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
                    .strokeBorder(
                        phase.usesDarkAppearance ? Color.white.opacity(0.10) : RepbasePalette.espresso.opacity(0.12),
                        lineWidth: 1
                    )
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
                    .strokeBorder(
                        phase.usesDarkAppearance ? Color.white.opacity(0.09) : RepbasePalette.espresso.opacity(0.08),
                        lineWidth: 0.75
                    )
            }
    }
}

struct WorkoutPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let phase: WorkoutVisualPhase

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
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
