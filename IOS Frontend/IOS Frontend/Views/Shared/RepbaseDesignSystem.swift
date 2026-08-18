//
//  RepbaseDesignSystem.swift
//  IOS Frontend
//
//  Shared visual language for a structured, professional interface.
//

import SwiftUI

enum RepbaseDesign {
    static let accent = Color(hex: 0x2563EB)
    static let success = Color(hex: 0x16835A)
    static let warning = Color(hex: 0xC46A16)
    static let danger = Color(hex: 0xC33A4A)

    static let pageInset: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
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
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: RepbaseDesign.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: RepbaseDesign.controlRadius)
                    .strokeBorder(timeOfDay.border, lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
