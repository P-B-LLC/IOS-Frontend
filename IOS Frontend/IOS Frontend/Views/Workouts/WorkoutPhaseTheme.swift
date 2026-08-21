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

    var canvasStart: Color {
        switch self {
        case .prepare: RepbasePalette.cream
        case .focus: Color(hex: 0x252220)
        case .recover: Color(hex: 0xF3F1EA)
        }
    }

    var canvasEnd: Color {
        switch self {
        case .prepare: Color(hex: 0xE2D2C6)
        case .focus: RepbasePalette.night
        case .recover: Color(hex: 0xDDE5DD)
        }
    }

    var canvasMiddle: Color {
        switch self {
        case .prepare: Color(hex: 0xF0E6DE)
        case .focus: Color(hex: 0x1E1C1B)
        case .recover: Color(hex: 0xE8ECE5)
        }
    }

    var accent: Color {
        switch self {
        case .prepare: RepbasePalette.caramel
        case .focus: Color(hex: 0xC69B7F)
        case .recover: RepbasePalette.sage
        }
    }

    var primaryText: Color {
        switch self {
        case .prepare: RepbasePalette.ink
        case .focus: RepbasePalette.cream
        case .recover: Color(hex: 0x26312B)
        }
    }

    var secondaryText: Color {
        switch self {
        case .prepare: RepbasePalette.muted
        case .focus: Color(hex: 0xCDBFB5)
        case .recover: Color(hex: 0x64746B)
        }
    }

    var surfaceStart: Color {
        switch self {
        case .prepare: RepbasePalette.paper
        case .focus: Color(hex: 0x312D2A)
        case .recover: Color(hex: 0xFAF9F4)
        }
    }

    var surfaceEnd: Color {
        switch self {
        case .prepare: Color(hex: 0xF1E7DF)
        case .focus: Color(hex: 0x282522)
        case .recover: Color(hex: 0xE5EAE4)
        }
    }

    var heroStart: Color {
        switch self {
        case .prepare: RepbasePalette.charcoal
        case .focus: Color(hex: 0x302A27)
        case .recover: Color(hex: 0x26312B)
        }
    }

    var heroEnd: Color {
        switch self {
        case .prepare: RepbasePalette.espresso
        case .focus: Color(hex: 0x59453B)
        case .recover: Color(hex: 0x60796B)
        }
    }

    var onAccent: Color {
        switch self {
        case .focus: RepbasePalette.charcoal
        case .prepare, .recover: RepbasePalette.cream
        }
    }

    var shadow: Color {
        switch self {
        case .prepare: RepbasePalette.espresso.opacity(0.14)
        case .focus: Color.black.opacity(0.26)
        case .recover: Color(hex: 0x385246).opacity(0.14)
        }
    }

    var usesDarkAppearance: Bool { self == .focus }
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
            .preferredColorScheme(phase.usesDarkAppearance ? .dark : .light)
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
                    .fill(
                        LinearGradient(
                            colors: [phase.surfaceStart, phase.surfaceEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: phase.shadow.opacity(phase == .focus ? 0.72 : 0.42), radius: phase == .focus ? 12 : 6, x: 0, y: 4)
                    .shadow(
                        color: phase.usesDarkAppearance
                            ? Color.white.opacity(0.035)
                            : Color.white.opacity(0.90),
                        radius: 2,
                        x: 0,
                        y: -1
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        phase == .focus ? Color.white.opacity(0.10) : RepbasePalette.espresso.opacity(0.09),
                        lineWidth: 0.75
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
                    .fill(
                        LinearGradient(
                            colors: [phase.surfaceStart, phase.surfaceEnd.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: phase.shadow.opacity(0.50), radius: 5, x: 0, y: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        phase == .focus ? Color.white.opacity(0.09) : RepbasePalette.espresso.opacity(0.08),
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
            .foregroundStyle(RepbasePalette.cream)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(phase == .focus ? phase.accent : RepbasePalette.charcoal)
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
