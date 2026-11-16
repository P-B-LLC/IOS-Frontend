//
//  PostTakesSheet.swift
//  IOS Frontend
//
//  The takes people have posted of one post, and the way to add yours.
//

import SwiftUI

/// Everybody's version of one post. Each row opens that take; the button
/// starts the reader's own, when the post's author allows one.
struct PostTakesSheet: View {
    let postID: Int
    let timeOfDay: HomeTimeOfDay
    var openPost: (Int) -> Void
    var startTake: () -> Void

    @Environment(SocialStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var takes: [FeedPost] { store.takesByPost[postID] ?? [] }
    private var post: FeedPost? { store.post(withID: postID) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(post?.takeCount ?? takes.count) takes")
                        .font(.community(.title3, weight: .bold))
                        .foregroundStyle(timeOfDay.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(timeOfDay.secondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.bottom, 8)

                if takes.isEmpty, store.loadingTakesFor.contains(postID) {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                } else if store.failedTakesFor.contains(postID), takes.isEmpty {
                    Button("Try again") { Task { await store.loadTakes(of: postID) } }
                        .font(.community(.subheadline, weight: .semibold))
                        .frame(minHeight: 44)
                } else {
                    ForEach(takes) { take in
                        Button {
                            dismiss()
                            openPost(take.id)
                        } label: {
                            row(take)
                        }
                        .buttonStyle(.plain)
                        .task {
                            // The last row asks for the next page.
                            if take.id == takes.last?.id, store.hasMoreTakes(of: postID) {
                                await store.loadTakes(of: postID, more: true)
                            }
                        }
                        Divider().overlay(timeOfDay.border)
                    }
                }

                if post?.viewerCanTake == true {
                    Button {
                        dismiss()
                        startTake()
                    } label: {
                        Label("Post your take", systemImage: "plus")
                            .font(.community(.footnote, weight: .semibold))
                            .foregroundStyle(timeOfDay.onPrimaryAction)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(timeOfDay.primaryActionSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .background(timeOfDay.surface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: postID) { await store.loadTakes(of: postID) }
    }

    private func row(_ take: FeedPost) -> some View {
        HStack(spacing: 12) {
            if let url = take.video?.thumbnailURL ?? take.feedImageURL {
                RemoteImage(url: url, maxPixel: 180) {
                    timeOfDay.surfaceRaised
                } failure: {
                    timeOfDay.surfaceRaised
                }
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(take.author.displayName)
                    .font(.community(.subheadline, weight: .semibold))
                    .foregroundStyle(timeOfDay.primaryText)
                    .lineLimit(1)
                let line = take.caption.isEmpty ? (take.workout?.title ?? take.meal?.name ?? "") : take.caption
                if !line.isEmpty {
                    Text(line)
                        .font(.community(.footnote))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(timeOfDay.secondaryText)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
