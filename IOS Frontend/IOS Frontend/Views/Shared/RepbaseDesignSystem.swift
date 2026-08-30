//
//  RepbaseDesignSystem.swift
//  IOS Frontend
//
//  Shared visual language for a structured, professional interface.
//

import SwiftUI

enum RepbaseDesign {
    static let accent = RepbasePalette.caramel
    /// Adaptive ink is black in Light mode and white in Dark mode. This keeps
    /// artwork and legacy direct uses visible while dedicated navigation
    /// surfaces continue to use `HomeTimeOfDay.ink`.
    static let ink = Color.primary
    static let onInk = Color(uiColor: .systemBackground)
    static let canvas = Color.repbaseDynamic(light: Color.white, dark: Color(hex: 0x1A1817))
    static let inset = RepbasePalette.oatmeal
    static let success = RepbasePalette.sage
    static let warning = Color(hex: 0xC46A16)
    static let danger = Color(hex: 0xC33A4A)

    static let pageInset: CGFloat = 18
    static let sectionSpacing: CGFloat = 22
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    static let featureRadius: CGFloat = 20

    /// Room a scrolling page must leave below its content for the floating
    /// bottom bar.
    ///
    /// The bar is inset on the `TabView`, which sits outside each tab's
    /// navigation stack, so its height never reaches these scroll views and
    /// every one of them has to leave the room itself. Kept here as one number
    /// because four of the five tabs left 28 points, and the last row of each
    /// of those pages could not be scrolled clear of the bar.
    // Tracks the bar's height. It was 118 when the bar carried labels; the
    // first icons-only pass cut both too far, so both came back part way.
    static let bottomBarClearance: CGFloat = 108
    static let deepShadow = RepbasePalette.espresso.opacity(0.12)
    static let softHighlight = Color.repbaseDynamic(
        light: Color.white.opacity(0.82),
        dark: Color.white.opacity(0.08)
    )
}

/// A quiet bounded surface for a true interactive module.
///
/// Earlier versions treated every section as a floating card. The approved
/// direction keeps related information in one continuous page and reserves
/// visible depth for controls people can actually open or change.
private struct RepbaseDepthSurfaceModifier: ViewModifier {
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(timeOfDay.surfaceRaised)
                    .shadow(
                        color: Color.repbaseDynamic(
                            light: RepbasePalette.espresso.opacity(0.07),
                            dark: Color.black.opacity(0.20)
                        ),
                        radius: 7,

                        x: 0,
                        y: 3
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        // Spelled out rather than border.opacity(...): border is
                        // itself dynamic now, and nesting one dynamic colour
                        // inside another resolves the inner one early. These are
                        // the two products, 0.10 x 0.72 and 0.12 x 0.42.
                        Color.repbaseDynamic(
                            light: RepbasePalette.espresso.opacity(0.072),
                            dark: Color.white.opacity(0.050)
                        ),

                        lineWidth: 1
                    )
            }
    }
}

/// A recessed area for selectors, input groups, and progress tracks.
private struct RepbaseInsetSurfaceModifier: ViewModifier {
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(timeOfDay.selectorSurface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        Color.repbaseDynamic(
                            light: Color.black.opacity(0.06),
                            dark: Color.black.opacity(0.28)
                        ),
                        lineWidth: 1
                    )

                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        Color.repbaseDynamic(
                            light: Color.white.opacity(0.86),
                            dark: Color.white.opacity(0.05)
                        ),
                        lineWidth: 1
                    )

                    .shadow(color: Color.white.opacity(0.45), radius: 1, x: 0, y: -1)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
    }
}

extension View {
    func repbaseDepthSurface(cornerRadius: CGFloat = RepbaseDesign.cardRadius) -> some View {
        modifier(RepbaseDepthSurfaceModifier(cornerRadius: cornerRadius))
    }

    func repbaseInsetSurface(cornerRadius: CGFloat = RepbaseDesign.controlRadius) -> some View {
        modifier(RepbaseInsetSurfaceModifier(cornerRadius: cornerRadius))
    }
}

/// A consistent title block for the app's top-level destinations.
struct RepbaseScreenHeader: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let eyebrow: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(.community(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(timeOfDay.accent)

            Text(title)
                .font(.community(size: 30, weight: .bold))
                .tracking(-0.65)
                .foregroundStyle(timeOfDay.canvasPrimaryText)

            if let detail {
                Text(detail)
                    .font(.community(size: 14, weight: .medium))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small section heading used before lists and dashboard modules.
struct RepbaseSectionHeader: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.community(size: 16, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(.community(size: 11, weight: .semibold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
        }
    }
}

struct RepbaseQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.homeTimeOfDay) private var timeOfDay

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.community(.subheadline, weight: .semibold))
            .foregroundStyle(timeOfDay.primaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .repbaseDepthSurface(cornerRadius: RepbaseDesign.controlRadius)
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The references use one decisive black control instead of tinting every
/// interaction. Blue remains available for progress and status information.
struct RepbasePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.community(.subheadline, weight: .bold))
            .foregroundStyle(RepbaseDesign.onInk)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(RepbaseDesign.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 5)
            .opacity(isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Compact actions that explain their destination with color and a leading
/// symbol instead of a generic arrow. These are intentionally small enough to
/// sit inside information-heavy rows without turning the whole row into a
/// floating card.
enum RepbaseTonalActionTone {
    case warm
    case primary
    case sage
    case outline

    func background(timeOfDay: HomeTimeOfDay) -> Color {
        switch self {
        case .warm:
            return .repbaseDynamic(
                light: Color(hex: 0xF0D6C4),
                dark: Color(hex: 0x3B2B25)
            )
        case .primary:
            return timeOfDay.primaryActionSurface
        case .sage:
            return .repbaseDynamic(
                light: Color(hex: 0xD6E8DE),
                dark: Color(hex: 0x22352D)
            )
        case .outline:
            return timeOfDay.surfaceRaised
        }
    }

    func foreground(timeOfDay: HomeTimeOfDay) -> Color {
        switch self {
        case .warm, .outline:
            return .repbaseDynamic(
                light: Color(hex: 0x9E4F33),
                dark: Color(hex: 0xF0AF8C)
            )
        case .primary:
            return timeOfDay.onPrimaryAction
        case .sage:
            return .repbaseDynamic(
                light: Color(hex: 0x386E59),
                dark: Color(hex: 0xA8D9C2)
            )
        }
    }

    func border(timeOfDay: HomeTimeOfDay) -> Color {
        switch self {
        case .outline:
            return .repbaseDynamic(
                light: Color(hex: 0xE3D6D1),
                dark: Color.white.opacity(0.14)
            )
        default:
            return .clear
        }
    }
}

struct RepbaseTonalActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
    }
}

/// Mirrors the approved Figma press: 0.955 scale and a two-point depression,
/// followed by a light spring overshoot on release. Reduce Motion keeps the
/// tonal state change while removing movement.
struct RepbaseTonalButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.homeTimeOfDay) private var timeOfDay

    let tone: RepbaseTonalActionTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.community(.caption, weight: .bold))
            .foregroundStyle(tone.foreground(timeOfDay: timeOfDay))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                tone.background(timeOfDay: timeOfDay),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tone.border(timeOfDay: timeOfDay), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.955 : 1))
            .offset(y: reduceMotion ? 0 : (configuration.isPressed ? 2 : 0))
            .animation(
                reduceMotion
                    ? .linear(duration: 0.01)
                    : .interpolatingSpring(mass: 0.55, stiffness: 330, damping: 18, initialVelocity: 0),
                value: configuration.isPressed
            )
    }
}

/// Arrow-free settings rows still need unmistakable touch feedback. The
/// three-point nudge and opacity dip are the approved Figma interaction.
struct RepbaseSettingsRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.76 : 1)
            .offset(x: reduceMotion ? 0 : (configuration.isPressed ? 3 : 0))
            .animation(
                reduceMotion
                    ? .linear(duration: 0.01)
                    : .interpolatingSpring(mass: 0.62, stiffness: 300, damping: 22, initialVelocity: 0),
                value: configuration.isPressed
            )
    }
}
