//
//  HomeTimeTheme.swift
//  IOS Frontend
//
//  Time-aware visual tokens for the Repbase home dashboard.
//

import SwiftUI

/// The warm end of the palette, kept from the soft luxury branch.
///
/// The screens merged from that branch name these colours directly rather than
/// going through `HomeTimeOfDay`, because they are fixed accents: a caramel
/// icon is caramel at every hour. The time-aware tokens below are what change
/// with the clock, and everything structural should still use those.
enum RepbasePalette {
    /// Light mode uses true white rather than a warm off-white. Keeping the
    /// aliases means existing screens inherit the change without duplicating
    /// appearance checks throughout the view hierarchy.
    static let cream = Color.white
    static let paper = Color.white
    static let oatmeal = Color(hex: 0xF2F2F2)
    static let sand = Color(hex: 0xD1D1D1)
    static let caramel = Color(hex: 0xF86722)
    static let cocoa = Color(hex: 0x6F5548)
    static let espresso = Color(hex: 0x493B35)
    static let charcoal = Color(hex: 0x242120)
    static let night = Color(hex: 0x171616)
    static let ink = Color(hex: 0x292421)
    static let muted = Color(hex: 0x8B786D)
    static let sage = Color(hex: 0x789182)
}

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
        case .dawn, .day: Color.white
        case .dusk: Color(hex: 0x896C5E)
        case .night: Color(hex: 0x252220)
        }
    }

    var canvasMiddle: Color {
        switch self {
        case .dawn, .day: Color.white
        case .dusk: Color(hex: 0x6A5147)
        case .night: Color(hex: 0x1D1B1A)
        }
    }

    var canvasEnd: Color {
        switch self {
        case .dawn, .day: Color.white
        case .dusk: Color(hex: 0x3F3430)
        case .night: RepbasePalette.night
        }
    }

    var primaryText: Color {
        usesDarkAppearance ? RepbasePalette.cream : RepbasePalette.ink
    }

    var secondaryText: Color {
        usesDarkAppearance ? Color(hex: 0xCDBFB5) : RepbasePalette.muted
    }

    var surface: Color {
        switch self {
        case .night: Color(hex: 0x292624)
        case .dawn, .day, .dusk: Color.white
        }
    }

    var surfaceRaised: Color {
        switch self {
        case .night: Color(hex: 0x332F2C)
        case .dawn, .day, .dusk: Color.white
        }
    }

    var selectorSurface: Color {
        usesDarkAppearance ? Color(hex: 0x3B3633) : RepbasePalette.oatmeal
    }

    var emptyDaySurface: Color {
        usesDarkAppearance ? Color(hex: 0x292624) : RepbasePalette.oatmeal
    }

    var plannedDaySurface: Color { RepbasePalette.espresso }
    var completedDaySurface: Color { RepbasePalette.paper }
    /// The brand accent stays constant when appearance changes.
    var accent: Color { RepbasePalette.caramel }
    var ink: Color { RepbasePalette.charcoal }

    /// Primary actions invert in dark canvas states so they remain the most
    /// visible control on the page. Persistent navigation continues to use
    /// `ink`; these tokens are reserved for actionable controls.
    var primaryActionSurface: Color {
        hasDarkCanvas ? Color.white : RepbasePalette.charcoal
    }

    var onPrimaryAction: Color {
        hasDarkCanvas ? RepbasePalette.ink : Color.white
    }

    var heroEnd: Color {
        switch self {
        case .dawn: Color(hex: 0x5D4A40)
        case .day: RepbasePalette.espresso
        case .dusk: Color(hex: 0x3A302D)
        case .night: Color(hex: 0x4A3A33)
        }
    }

    var border: Color {
        usesDarkAppearance ? Color.white.opacity(0.12) : RepbasePalette.espresso.opacity(0.10)
    }

    var shadow: Color {
        usesDarkAppearance ? Color.black.opacity(0.26) : RepbasePalette.espresso.opacity(0.14)
    }

    // MARK: - Drawn straight on the canvas
    //
    // Almost everything on the home page sits on a raised surface, which stays
    // light at every hour, so `primaryText` follows the appearance. Content
    // drawn directly on the canvas cannot: from dusk the canvas itself is dark,
    // and near-black text disappears into it. These follow the canvas instead.

    /// Whether the canvas behind unraised content is dark at this hour.
    var hasDarkCanvas: Bool { self == .dusk || self == .night }

    var canvasPrimaryText: Color {
        hasDarkCanvas ? RepbasePalette.cream : RepbasePalette.ink
    }

    var canvasSecondaryText: Color {
        hasDarkCanvas ? Color.white.opacity(0.72) : RepbasePalette.muted
    }

    var canvasBorder: Color {
        hasDarkCanvas ? Color.white.opacity(0.16) : RepbasePalette.espresso.opacity(0.12)
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
                RepbaseAmbientBackdrop(timeOfDay: timeOfDay)
            }
            .environment(\.homeTimeOfDay, timeOfDay)
            .environment(\.workoutVisualPhase, timeOfDay.usesDarkAppearance ? .focus : .prepare)
            .tint(timeOfDay.accent)
            .preferredColorScheme(timeOfDay.usesDarkAppearance ? .dark : .light)
    }
}

/// A quiet matte canvas. Depth comes from the product modules, matching the
/// supplied hardware and automotive references rather than decorative art.
private struct RepbaseAmbientBackdrop: View {
    let timeOfDay: HomeTimeOfDay

    var body: some View {
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
            .repbaseDepthSurface(cornerRadius: 12)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
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
            .foregroundStyle(timeOfDay.onPrimaryAction)
            .padding(.horizontal, 15)
            .frame(height: 42)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(timeOfDay.primaryActionSurface)
                        .shadow(color: timeOfDay.shadow.opacity(0.75), radius: 8, x: 0, y: 4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.80 : 1) : 0.42)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
