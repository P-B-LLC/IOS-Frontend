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
    static let canvas = RepbasePalette.cream
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

    /// Bottom padding for the two pages that also carry the floating quick
    /// action button.
    ///
    /// A smaller button still sits over whatever is beneath it, so shrinking
    /// alone cannot stop it covering the last row — the content has to be able
    /// to scroll past it. This is the bar's clearance plus the button and a
    /// gap, and it is separate from `bottomBarClearance` because the three
    /// pages without a button should not pay for one.
    static let quickActionClearance: CGFloat = bottomBarClearance + 60
    static let deepShadow = RepbasePalette.espresso.opacity(0.12)
    static let softHighlight = RepbasePalette.paper.opacity(0.82)
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
                        color: timeOfDay.usesDarkAppearance
                            ? Color.black.opacity(0.20)
                            : RepbasePalette.espresso.opacity(0.07),
                        radius: 7,
                        x: 0,
                        y: 3
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        timeOfDay.border.opacity(timeOfDay.usesDarkAppearance ? 0.42 : 0.72),
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
                    .strokeBorder(Color.black.opacity(timeOfDay.usesDarkAppearance ? 0.28 : 0.06), lineWidth: 1)
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(timeOfDay.usesDarkAppearance ? 0.05 : 0.86), lineWidth: 1)
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
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(timeOfDay.accent)

            Text(title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.65)
                .foregroundStyle(timeOfDay.canvasPrimaryText)

            if let detail {
                Text(detail)
                    .font(.system(size: 14, weight: .medium))
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
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .semibold))
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
            .font(.subheadline.weight(.semibold))
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
            .font(.subheadline.weight(.bold))
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
