//
//  HomeTimeTheme.swift
//  IOS Frontend
//
//  Time-aware visual tokens for the Repbase home dashboard.
//

import SwiftUI

/// The one appearance choice used by every Repbase screen.
///
/// Kept in `UserDefaults` through `AppStorage`: appearance is a device-level
/// preference, not account data, and it must be available before sign-in so
/// the launch and authentication screens do not flash the wrong theme.
enum RepbaseAppearancePreference: String, CaseIterable, Identifiable {
    static let storageKey = "repbase.appearance"

    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .light ? "sun.max.fill" : "moon.fill" }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }

    static var current: RepbaseAppearancePreference {
        let raw = UserDefaults.standard.string(forKey: storageKey)
        return RepbaseAppearancePreference(rawValue: raw ?? "") ?? .light
    }
}

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
    /// A surface in every one of its uses -- fills, backgrounds and one
    /// progress-ring track -- so it follows the trait. Its neighbours cream and
    /// sand are foregrounds and stay fixed: turning those dynamic would put
    /// dark text on the dark surfaces they are drawn against.
    static let oatmeal = Color.repbaseDynamic(light: Color(hex: 0xF2F2F2), dark: Color(hex: 0x2C2927))
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
        // Compatibility initializer for the views that already ask for a
        // `HomeTimeOfDay`. The clock no longer chooses appearance; the saved
        // user preference does. Keeping the type avoids a risky app-wide API
        // migration while removing the old dawn/day/dusk/night behavior.
        self = RepbaseAppearancePreference.current == .dark ? .night : .day
    }

    var label: String { usesDarkAppearance ? "DARK" : "LIGHT" }

    var usesDarkAppearance: Bool { RepbaseAppearancePreference.current == .dark }

    var canvasStart: Color {
        Color(uiColor: .systemBackground)
    }

    var canvasMiddle: Color {
        Color(uiColor: .systemBackground)
    }

    var canvasEnd: Color {
        Color(uiColor: .systemBackground)
    }

    var primaryText: Color {
        Color.primary
    }

    var secondaryText: Color {
        Color.secondary
    }

    var surface: Color {
        Color(uiColor: .systemBackground)
    }

    var surfaceRaised: Color {
        .repbaseDynamic(light: Color.white, dark: Color(hex: 0x252220))
    }

    var selectorSurface: Color {
        .repbaseDynamic(light: RepbasePalette.oatmeal, dark: Color(hex: 0x2C2927))
    }

    var emptyDaySurface: Color {
        .repbaseDynamic(light: RepbasePalette.oatmeal, dark: Color(hex: 0x252220))
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
        .repbaseDynamic(light: RepbasePalette.charcoal, dark: Color.white)
    }

    var onPrimaryAction: Color {
        .repbaseDynamic(light: Color.white, dark: RepbasePalette.ink)
    }

    var heroEnd: Color {
        .repbaseDynamic(light: RepbasePalette.espresso, dark: Color(hex: 0x332F2C))
    }

    var border: Color {
        .repbaseDynamic(
            light: RepbasePalette.espresso.opacity(0.10),
            dark: Color.white.opacity(0.12)
        )
    }

    var shadow: Color {
        .repbaseDynamic(
            light: RepbasePalette.espresso.opacity(0.14),
            dark: Color.black.opacity(0.26)
        )
    }

    // MARK: - Drawn straight on the canvas
    //
    // Almost everything on the home page sits on a raised surface, which stays
    // light at every hour, so `primaryText` follows the appearance. Content
    // drawn directly on the canvas cannot: from dusk the canvas itself is dark,
    // and near-black text disappears into it. These follow the canvas instead.

    /// Whether the canvas behind unraised content is dark at this hour.
    var hasDarkCanvas: Bool { usesDarkAppearance }

    var canvasPrimaryText: Color {
        Color.primary
    }

    var canvasSecondaryText: Color {
        Color.secondary
    }

    var canvasBorder: Color {
        .repbaseDynamic(
            light: RepbasePalette.espresso.opacity(0.12),
            dark: Color.white.opacity(0.16)
        )
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
            .environment(\.workoutVisualPhase, .prepare)
            .tint(timeOfDay.accent)
    }
}

/// A quiet matte canvas. Depth comes from the product modules, matching the
/// supplied hardware and automotive references rather than decorative art.
private struct RepbaseAmbientBackdrop: View {
    let timeOfDay: HomeTimeOfDay

    var body: some View {
        Color(uiColor: .systemBackground).ignoresSafeArea()
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
            .font(.community(.body, weight: .semibold))
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
            .font(.community(.subheadline, weight: .bold))
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
