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
        case .prepare: Color(hex: 0xF7F7F8)
        case .focus: Color(hex: 0x2C252A)
        case .recover: Color(hex: 0xF3F7F5)
        }
    }

    var canvasEnd: Color {
        switch self {
        case .prepare: Color(hex: 0xE8D4CA)
        case .focus: Color(hex: 0x151216)
        case .recover: Color(hex: 0xD9E7E0)
        }
    }

    var canvasMiddle: Color {
        switch self {
        case .prepare: Color(hex: 0xF4F0EF)
        case .focus: Color(hex: 0x211B20)
        case .recover: Color(hex: 0xE8F0EC)
        }
    }

    var accent: Color {
        switch self {
        case .prepare: Color(hex: 0xF86722)
        case .focus: Color(hex: 0xFF7640)
        case .recover: Color(hex: 0x5DAA86)
        }
    }

    var primaryText: Color {
        switch self {
        case .prepare: Color(hex: 0x1B1415)
        case .focus: Color(hex: 0xF7F7F8)
        case .recover: Color(hex: 0x17211D)
        }
    }

    var secondaryText: Color {
        switch self {
        case .prepare: Color(hex: 0x67534D)
        case .focus: Color(hex: 0xCBBDBA)
        case .recover: Color(hex: 0x5F756A)
        }
    }

    var surfaceStart: Color {
        switch self {
        case .prepare: Color(hex: 0xF9F9FA)
        case .focus: Color(hex: 0x3B3237)
        case .recover: Color(hex: 0xF9FCFA)
        }
    }

    var surfaceEnd: Color {
        switch self {
        case .prepare: Color(hex: 0xE6D9D3)
        case .focus: Color(hex: 0x292226)
        case .recover: Color(hex: 0xDFEBE5)
        }
    }

    var heroStart: Color {
        switch self {
        case .prepare: Color(hex: 0x1B1415)
        case .focus: Color(hex: 0x352728)
        case .recover: Color(hex: 0x17211D)
        }
    }

    var heroEnd: Color {
        switch self {
        case .prepare: Color(hex: 0x67534D)
        case .focus: Color(hex: 0x673326)
        case .recover: Color(hex: 0x5A8A73)
        }
    }

    var onAccent: Color {
        switch self {
        case .focus: Color(hex: 0x1B1415)
        case .prepare, .recover: Color(hex: 0xF7F7F8)
        }
    }

    var shadow: Color {
        switch self {
        case .prepare: Color(hex: 0x67534D).opacity(0.20)
        case .focus: Color.black.opacity(0.30)
        case .recover: Color(hex: 0x385246).opacity(0.22)
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
            startPoint: .topLeading,
            endPoint: .bottomTrailing
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
                    .shadow(color: phase.shadow, radius: phase == .focus ? 16 : 12, x: 5, y: 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        phase == .focus ? Color.white.opacity(0.16) : Color.white.opacity(0.72),
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
                    .fill(
                        LinearGradient(
                            colors: [phase.surfaceStart, phase.surfaceEnd.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: phase.shadow.opacity(0.55), radius: 5, x: 2, y: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        phase == .focus ? Color.white.opacity(0.12) : Color.white.opacity(0.64),
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
            .foregroundStyle(phase.onAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [phase.accent, phase.accent.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: phase.accent.opacity(0.30), radius: 13, x: 4, y: 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension View {
    func workoutCard() -> some View {
        repbaseCard(contentPadding: 16, cornerRadius: 17)
    }

    func repbaseCard(contentPadding: CGFloat = 12, cornerRadius: CGFloat = 16) -> some View {
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

    func repbaseControlSurface(cornerRadius: CGFloat = 12) -> some View {
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
