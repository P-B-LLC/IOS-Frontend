//
//  EditorialFormComponents.swift
//  IOS Frontend
//
//  Shared soft-luxury form components used by focused creation screens.
//

import SwiftUI

/// A small product signature for destination and workflow headers.
/// Authentication may use the mark as a hero; utility pages keep it compact
/// so Rytivo remains recognizable without competing with the page title.
struct RytivoBrandLockup: View {
    var size: CGFloat = 24

    @Environment(\.homeTimeOfDay) private var timeOfDay

    var body: some View {
        HStack(spacing: max(7, size * 0.28)) {
            Image("RytivoLogoMark")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)

            Text("Rytivo")
                .font(.community(size: max(15, size * 0.67), weight: .bold))
                .tracking(-0.35)
                .foregroundStyle(timeOfDay.canvasPrimaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rytivo")
    }
}

struct EditorialFormHeader: View {
    enum LeadingAction: Equatable {
        case cancel
        case back
    }

    let title: String
    let leadingAction: LeadingAction
    let saveTitle: String
    let canSave: Bool
    let onDismiss: () -> Void
    let onSave: () -> Void
    var showsSaveAction = true

    @Environment(\.homeTimeOfDay) private var timeOfDay

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                RytivoBrandLockup(size: 22)
                Spacer()
            }

            HStack {
            Button(action: onDismiss) {
                if leadingAction == .back {
                    Image(systemName: "chevron.left")
                        .font(.community(.body, weight: .semibold))
                        .frame(width: 42, height: 42)
                } else {
                    Text("Cancel")
                        .font(.community(.subheadline, weight: .medium))
                        .frame(minWidth: 48, minHeight: 42, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(timeOfDay.canvasPrimaryText)

            Spacer()
            Text(title)
                .font(.community(.headline, weight: .bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Spacer()

            if showsSaveAction {
                Button(action: onSave) {
                    Text(saveTitle)
                    .font(.community(.subheadline, weight: .bold))
                    .foregroundStyle(timeOfDay.accent)
                    .frame(minWidth: 48, minHeight: 42, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.35)
            } else {
                Color.clear.frame(width: 48, height: 42)
            }
            }
        }
        .padding(.top, 6)
    }
}

struct EditorialSectionTitle: View {
    let title: String
    var detail: String? = nil

    @Environment(\.homeTimeOfDay) private var timeOfDay

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.community(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            if let detail {
                Text(detail)
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EditorialRuleGroup<Content: View>: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 16)
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(timeOfDay.border, lineWidth: 1)
            }
            .shadow(color: timeOfDay.shadow.opacity(0.55), radius: 9, x: 0, y: 5)
    }
}

struct EditorialRuleRow<Content: View>: View {
    @Environment(\.homeTimeOfDay) private var timeOfDay
    let showsDivider: Bool
    let content: Content

    init(showsDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.showsDivider = showsDivider
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) { content }
            .frame(minHeight: 54)
            .overlay(alignment: .bottom) {
                if showsDivider {
                    Rectangle().fill(timeOfDay.border.opacity(0.72)).frame(height: 1)
                }
            }
    }
}

struct EditorialPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.homeTimeOfDay) private var timeOfDay

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Image(systemName: "arrow.right")
        }
        .font(.community(.headline, weight: .bold))
        .foregroundStyle(timeOfDay.onPrimaryAction)
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(timeOfDay.primaryActionSurface)
                .shadow(color: timeOfDay.shadow.opacity(0.72), radius: 9, x: 0, y: 5)
        }
        .opacity(isEnabled ? (configuration.isPressed ? 0.62 : 1) : 0.35)
    }
}
