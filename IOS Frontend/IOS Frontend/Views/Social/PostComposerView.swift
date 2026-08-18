//
//  PostComposerView.swift
//  IOS Frontend
//
//  Sharing a workout, meal or planner entry to the feed.
//

import SwiftUI

/// What is being shared, and the caption to put on it.
///
/// The sheet sends the id and nothing else. The server reads the workout or
/// meal itself and builds the copy that goes out, so nothing typed here can
/// change what the post says was done.
struct PostComposerView: View {
    @Environment(SocialStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let kind: PostKind
    let sourceID: Int
    /// What the thing being shared is called, so the sheet can name it.
    let subject: String

    @State private var caption = ""
    @State private var visibility: PostVisibility = .publicToAll

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(timeOfDay: timeOfDay)
                    captionField(timeOfDay: timeOfDay)
                    visibilityPicker(timeOfDay: timeOfDay)

                    if let message = store.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    postButton(timeOfDay: timeOfDay)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .homeTimeScreen(timeOfDay)
        }
        .onAppear { store.clearError() }
    }

    private func header(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(timeOfDay.canvasPrimaryText)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("SHARE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(timeOfDay.accent)
                Text(subject)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func captionField(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Caption")
                .font(.caption.weight(.semibold))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            TextField("Say something about it", text: $caption, axis: .vertical)
                .lineLimit(3...6)
                .padding(13)
                .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 15))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(timeOfDay.border, lineWidth: 1)
                }
            Text("\(caption.count)/300")
                .font(.caption2)
                .foregroundStyle(
                    caption.count > 300 ? Color.red : timeOfDay.canvasSecondaryText
                )
        }
    }

    private func visibilityPicker(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Who can see it")
                .font(.caption.weight(.semibold))
                .foregroundStyle(timeOfDay.canvasSecondaryText)

            VStack(spacing: 0) {
                ForEach(PostVisibility.allCases) { option in
                    Button {
                        visibility = option
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.symbol)
                                .frame(width: 22)
                                .foregroundStyle(
                                    option == visibility
                                        ? timeOfDay.accent
                                        : timeOfDay.secondaryText
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(timeOfDay.primaryText)
                                Text(option.explanation)
                                    .font(.caption2)
                                    .foregroundStyle(timeOfDay.secondaryText)
                            }
                            Spacer(minLength: 0)
                            if option == visibility {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(timeOfDay.accent)
                            }
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if option != PostVisibility.allCases.last {
                        Divider().opacity(0.35).padding(.leading, 47)
                    }
                }
            }
            .background(timeOfDay.surfaceRaised, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(timeOfDay.border, lineWidth: 1)
            }
        }
    }

    private func postButton(timeOfDay: HomeTimeOfDay) -> some View {
        Button {
            Task {
                let sent = await store.post(
                    kind: kind,
                    sourceID: sourceID,
                    caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                    visibility: visibility
                )
                if sent { dismiss() }
            }
        } label: {
            HStack(spacing: 9) {
                if store.isPosting { ProgressView().tint(.white) }
                Text("Post")
                Image(systemName: "arrow.up.right")
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(timeOfDay.accent, in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .disabled(store.isPosting || caption.count > 300)
        .opacity(caption.count > 300 ? 0.42 : 1)
    }
}
