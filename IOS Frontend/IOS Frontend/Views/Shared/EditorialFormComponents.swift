//
//  EditorialFormComponents.swift
//  IOS Frontend
//
//  Shared soft-luxury form components used by focused creation screens.
//

import SwiftUI

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

    @Environment(\.homeTimeOfDay) private var timeOfDay

    var body: some View {
        HStack {
            Button(action: onDismiss) {
                if leadingAction == .back {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(timeOfDay.border, lineWidth: 1)
                        }
                } else {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 13)
                        .frame(height: 40)
                        .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 13))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(timeOfDay.canvasPrimaryText)

            Spacer()
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Spacer()

            Button(action: onSave) {
                HStack(spacing: 6) {
                    Text(saveTitle)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RepbasePalette.cream)
                .padding(.horizontal, 13)
                .frame(height: 40)
                .background(timeOfDay.ink, in: RoundedRectangle(cornerRadius: 13))
            }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.35)
        }
        .frame(height: 48)
    }
}

struct EditorialSectionTitle: View {
    let title: String
    var detail: String? = nil

    @Environment(\.homeTimeOfDay) private var timeOfDay

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            if let detail {
                Text(detail)
                    .font(.caption)
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
        .font(.headline.weight(.bold))
        .foregroundStyle(RepbasePalette.cream)
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(timeOfDay.ink)
                .shadow(color: timeOfDay.shadow.opacity(0.72), radius: 9, x: 0, y: 5)
        }
        .opacity(isEnabled ? (configuration.isPressed ? 0.62 : 1) : 0.35)
    }
}
