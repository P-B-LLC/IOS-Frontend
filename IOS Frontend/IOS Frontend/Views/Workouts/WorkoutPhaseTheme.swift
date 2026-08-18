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
        case .prepare: Color(hex: 0xF4F6F8)
        case .focus: Color(hex: 0x111827)
        case .recover: Color(hex: 0xF2F7F5)
        }
    }

    var canvasEnd: Color {
        switch self {
        case .prepare: Color(hex: 0xE9EDF2)
        case .focus: Color(hex: 0x0B1120)
        case .recover: Color(hex: 0xE4EFEA)
        }
    }

    var canvasMiddle: Color {
        switch self {
        case .prepare: Color(hex: 0xF1F3F6)
        case .focus: Color(hex: 0x0F172A)
        case .recover: Color(hex: 0xECF3F0)
        }
    }

    var accent: Color {
        switch self {
        case .prepare: RepbaseDesign.accent
        case .focus: Color(hex: 0x4F8BFF)
        case .recover: RepbaseDesign.success
        }
    }

    var primaryText: Color {
        switch self {
        case .prepare: Color(hex: 0x111827)
        case .focus: Color(hex: 0xF8FAFC)
        case .recover: Color(hex: 0x14251E)
        }
    }

    var secondaryText: Color {
        switch self {
        case .prepare: Color(hex: 0x667085)
        case .focus: Color(hex: 0xA8B3C4)
        case .recover: Color(hex: 0x60756B)
        }
    }

    var surfaceStart: Color {
        switch self {
        case .prepare: Color.white
        case .focus: Color(hex: 0x1B263B)
        case .recover: Color(hex: 0xF9FCFA)
        }
    }

    var surfaceEnd: Color {
        switch self {
        case .prepare: Color(hex: 0xF8FAFC)
        case .focus: Color(hex: 0x182235)
        case .recover: Color(hex: 0xF1F7F4)
        }
    }

    var heroStart: Color {
        switch self {
        case .prepare: Color(hex: 0x182235)
        case .focus: Color(hex: 0x182235)
        case .recover: Color(hex: 0x173127)
        }
    }

    var heroEnd: Color {
        switch self {
        case .prepare: Color(hex: 0x263B5E)
        case .focus: Color(hex: 0x1D4ED8)
        case .recover: Color(hex: 0x246044)
        }
    }

    var onAccent: Color {
        switch self {
        case .focus: Color.white
        case .prepare, .recover: Color.white
        }
    }

    var shadow: Color {
        switch self {
        case .prepare: Color.black.opacity(0.08)
        case .focus: Color.black.opacity(0.30)
        case .recover: Color(hex: 0x385246).opacity(0.10)
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
                    .shadow(color: phase.shadow.opacity(0.78), radius: 14, x: 0, y: 7)
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
                        phase == .focus ? Color.white.opacity(0.12) : Color(hex: 0xD7DCE4),
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
                    .shadow(color: Color.black.opacity(0.10), radius: 4, x: 3, y: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        phase == .focus ? Color.white.opacity(0.12) : Color(hex: 0xD7DCE4),
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
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [RepbaseDesign.ink, Color.black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
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
