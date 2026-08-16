//
//  EditorialFormComponents.swift
//  IOS Frontend
//
//  Quiet, line-based form components used by focused creation screens.
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
                        .overlay { Circle().strokeBorder(timeOfDay.canvasBorder, lineWidth: 1) }
                } else {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .frame(minWidth: 58, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(timeOfDay.canvasPrimaryText)

            Spacer()
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Spacer()

            Button(saveTitle, action: onSave)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(canSave ? timeOfDay.accent : timeOfDay.canvasSecondaryText.opacity(0.45))
                .frame(minWidth: 58, alignment: .trailing)
                .buttonStyle(.plain)
                .disabled(!canSave)
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
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.25)
                .foregroundStyle(timeOfDay.accent)
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
            .overlay(alignment: .top) {
                Rectangle().fill(timeOfDay.canvasBorder).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(timeOfDay.canvasBorder).frame(height: 1)
            }
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
                    Rectangle().fill(timeOfDay.canvasBorder.opacity(0.72)).frame(height: 1)
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
        .foregroundStyle(timeOfDay.accent)
        .padding(.horizontal, 2)
        .frame(height: 56)
        .overlay(alignment: .top) {
            Rectangle().fill(timeOfDay.accent).frame(height: 2)
        }
        .opacity(isEnabled ? (configuration.isPressed ? 0.62 : 1) : 0.35)
    }
}
