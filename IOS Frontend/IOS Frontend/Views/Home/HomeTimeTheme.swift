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
        case .dawn: Color(hex: 0xF7F7F8)
        case .day: Color(hex: 0xF7F7F8)
        case .dusk: Color(hex: 0xC9A89A)
        case .night: Color(hex: 0x0E0A0B)
        }
    }

    var canvasMiddle: Color {
        switch self {
        case .dawn: Color(hex: 0xF4ECE8)
        case .day: Color(hex: 0xEFEFEF)
        case .dusk: Color(hex: 0x9A7468)
        case .night: Color(hex: 0x151012)
        }
    }

    var canvasEnd: Color {
        switch self {
        case .dawn: Color(hex: 0xEEDBD1)
        case .day: Color(hex: 0xCFCFD0)
        case .dusk: Color(hex: 0x67534D)
        case .night: Color(hex: 0x1B1415)
        }
    }

    var primaryText: Color {
        usesDarkAppearance ? Color(hex: 0xF7F7F8) : Color(hex: 0x1B1415)
    }

    var secondaryText: Color {
        usesDarkAppearance ? Color(hex: 0xACA6A5) : Color(hex: 0x67534D)
    }

    var surface: Color {
        switch self {
        case .night: Color(hex: 0x1B1415)
        case .dusk: Color(hex: 0xE6D9D3)
        case .dawn, .day: Color(hex: 0xF9F9FA)
        }
    }

    var surfaceRaised: Color {
        switch self {
        case .night: Color(hex: 0x2C2426)
        case .dusk: Color(hex: 0xF0E6E1)
        case .dawn, .day: .white
        }
    }

    var selectorSurface: Color {
        usesDarkAppearance ? Color(hex: 0x2C2426) : surface.opacity(0.94)
    }

    var emptyDaySurface: Color {
        usesDarkAppearance ? Color(hex: 0x1B1415) : Color(hex: 0xE8E5E5)
    }

    var plannedDaySurface: Color { Color(hex: 0x67534D) }
    var completedDaySurface: Color { Color(hex: 0xF9F9FA) }
    var accent: Color { Color(hex: 0xF86722) }
    var ink: Color { Color(hex: 0x1B1415) }

    var heroEnd: Color {
        switch self {
        case .dawn: Color(hex: 0x67534D)
        case .day: Color(hex: 0x2C2426)
        case .dusk, .night: Color(hex: 0x5B2414)
        }
    }

    var border: Color {
        usesDarkAppearance ? Color.white.opacity(0.13) : Color.white.opacity(0.72)
    }

    var shadow: Color {
        usesDarkAppearance ? Color.black.opacity(0.42) : Color(hex: 0x67534D).opacity(0.22)
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
        hasDarkCanvas ? Color(hex: 0xFFFFFF) : Color(hex: 0x1B1415)
    }

    var canvasSecondaryText: Color {
        hasDarkCanvas ? Color.white.opacity(0.72) : Color(hex: 0x67534D)
    }

    var canvasBorder: Color {
        hasDarkCanvas ? Color.white.opacity(0.24) : Color.white.opacity(0.72)
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
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .environment(\.homeTimeOfDay, timeOfDay)
            .tint(timeOfDay.accent)
            .preferredColorScheme(timeOfDay.usesDarkAppearance ? .dark : .light)
    }
}

extension View {
    func homeTimeScreen(_ timeOfDay: HomeTimeOfDay) -> some View {
        modifier(HomeTimeScreenModifier(timeOfDay: timeOfDay))
    }
}
