//
//  HomeTimeTheme.swift
//  IOS Frontend
//
//  Time-aware visual tokens for the Repbase home dashboard.
//

import SwiftUI

enum HomeTimeOfDay: String, Sendable, Equatable {
    case dawn
    case day
    case dusk
    case night

    init(date: Date, calendar: Calendar = .current) {
        switch calendar.component(.hour, from: date) {
        case 5..<10: self = .dawn
        case 10..<17: self = .day
        case 17..<21: self = .dusk
        default: self = .night
        }
    }

    var label: String { rawValue.uppercased() }

    var usesDarkAppearance: Bool { self == .night }

    var canvasStart: Color {
        switch self {
        case .dawn: Color(hex: 0xF5F7FA)
        case .day: Color(hex: 0xF4F6F8)
        case .dusk: Color(hex: 0xF0F2F6)
        case .night: Color(hex: 0x111827)
        }
    }

    var canvasMiddle: Color {
        switch self {
        case .dawn: Color(hex: 0xF1F4F8)
        case .day: Color(hex: 0xF1F3F6)
        case .dusk: Color(hex: 0xE9EDF3)
        case .night: Color(hex: 0x0F172A)
        }
    }

    var canvasEnd: Color {
        switch self {
        case .dawn: Color(hex: 0xE8EDF3)
        case .day: Color(hex: 0xE9EDF2)
        case .dusk: Color(hex: 0xE2E7EF)
        case .night: Color(hex: 0x0B1120)
        }
    }

    var primaryText: Color {
        usesDarkAppearance ? Color(hex: 0xF8FAFC) : Color(hex: 0x111827)
    }

    var secondaryText: Color {
        usesDarkAppearance ? Color(hex: 0xA8B3C4) : Color(hex: 0x667085)
    }

    var surface: Color {
        switch self {
        case .night: Color(hex: 0x172033)
        case .dawn, .day, .dusk: Color(hex: 0xF8FAFC)
        }
    }

    var surfaceRaised: Color {
        switch self {
        case .night: Color(hex: 0x1B263B)
        case .dawn, .day, .dusk: .white
        }
    }

    var selectorSurface: Color {
        usesDarkAppearance ? Color(hex: 0x202C42) : Color(hex: 0xE8ECF2)
    }

    var emptyDaySurface: Color {
        usesDarkAppearance ? Color(hex: 0x182235) : Color(hex: 0xEEF1F5)
    }

    var plannedDaySurface: Color { Color(hex: 0x344054) }
    var completedDaySurface: Color { Color(hex: 0xF8FAFC) }
    var accent: Color { RepbaseDesign.accent }
    var ink: Color { Color(hex: 0x111827) }

    var heroEnd: Color {
        switch self {
        case .dawn: Color(hex: 0x334155)
        case .day: Color(hex: 0x1E293B)
        case .dusk: Color(hex: 0x24324A)
        case .night: Color(hex: 0x1D4ED8)
        }
    }

    var border: Color {
        usesDarkAppearance ? Color.white.opacity(0.12) : Color(hex: 0xD7DCE4)
    }

    var shadow: Color {
        usesDarkAppearance ? Color.black.opacity(0.28) : Color.black.opacity(0.08)
    }

    // MARK: - Drawn straight on the canvas
    //
    // Almost everything on the home page sits on a raised surface, which stays
    // light at every hour, so `primaryText` follows the appearance. Content
    // drawn directly on the canvas cannot: from dusk the canvas itself is dark,
    // and near-black text disappears into it. These follow the canvas instead.

    /// Whether the canvas behind unraised content is dark at this hour.
    var hasDarkCanvas: Bool { self == .night }

    var canvasPrimaryText: Color {
        hasDarkCanvas ? Color(hex: 0xF8FAFC) : Color(hex: 0x111827)
    }

    var canvasSecondaryText: Color {
        hasDarkCanvas ? Color(hex: 0xA8B3C4) : Color(hex: 0x667085)
    }

    var canvasBorder: Color {
        hasDarkCanvas ? Color.white.opacity(0.14) : Color(hex: 0xD7DCE4)
    }
}

private struct HomeTimeOfDayKey: EnvironmentKey {
    static let defaultValue = HomeTimeOfDay.day
}

extension EnvironmentValues {
    var homeTimeOfDay: HomeTimeOfDay {
        get { self[HomeTimeOfDayKey.self] }
        set { self[HomeTimeOfDayKey.self] = newValue }
    }
}

private struct HomeTimeScreenModifier: ViewModifier {
    let timeOfDay: HomeTimeOfDay

    func body(content: Content) -> some View {
        content
            .foregroundStyle(timeOfDay.primaryText)
            .background {
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: timeOfDay.canvasStart, location: 0),
                        .init(color: timeOfDay.canvasMiddle, location: 0.56),
                        .init(color: timeOfDay.canvasEnd, location: 1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .environment(\.homeTimeOfDay, timeOfDay)
            .environment(\.workoutVisualPhase, timeOfDay.usesDarkAppearance ? .focus : .prepare)
            .tint(timeOfDay.accent)
            .preferredColorScheme(timeOfDay.usesDarkAppearance ? .dark : .light)
    }
}

extension View {
    func homeTimeScreen(_ timeOfDay: HomeTimeOfDay) -> some View {
        modifier(HomeTimeScreenModifier(timeOfDay: timeOfDay))
    }
}

/// The tactile circular navigation control used for Back and Settings.
struct RepbaseSculptedIconButtonStyle: ButtonStyle {
    let timeOfDay: HomeTimeOfDay

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(timeOfDay.primaryText)
            .frame(width: 44, height: 44)
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(timeOfDay.border, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// A compact, unmistakable primary navigation action such as Save or Goals.
struct RepbaseAccentCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let timeOfDay: HomeTimeOfDay

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 15)
            .frame(height: 42)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(timeOfDay.accent)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.80 : 1) : 0.42)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
