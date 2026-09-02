//
//  PostActionBar.swift
//  IOS Frontend
//
//  Like, comment, repost, share — the row under every post.
//
//  Counts sit beside their action rather than in a summary line above, so the
//  number and the way to change it are the same target. A count of zero is
//  left blank: "0" invites a reading of the post as ignored, when in truth
//  nobody has got to it yet.
//

import SwiftUI

struct PostActionBar: View {
    let post: FeedPost
    let timeOfDay: HomeTimeOfDay
    /// Raises the threads. Set everywhere the bar is drawn — the post's
    /// own page included, where they are a sheet like anywhere else.
    var openComments: (() -> Void)?

    @Environment(SocialStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            action(
                symbol: "bubble.left",
                count: post.commentCount,
                tint: timeOfDay.secondaryText,
                label: "Comments"
            ) {
                openComments?()
            }
            .disabled(openComments == nil)

            action(
                // One symbol in two colours. There is no filled counterpart
                // to arrow.2.squarepath, and naming a variant that does not
                // exist drew nothing at all — the reposted state was a bare
                // number with no icon beside it.
                symbol: "arrow.2.squarepath",
                count: post.repostCount,
                tint: post.viewerHasReposted ? RepbaseDesign.success : timeOfDay.secondaryText,
                label: post.viewerHasReposted ? "Undo repost" : "Repost"
            ) {
                Task { await store.toggleRepost(post) }
            }

            action(
                symbol: post.viewerHasLiked ? "heart.fill" : "heart",
                count: post.likeCount,
                tint: post.viewerHasLiked ? Color(hex: 0xE0446B) : timeOfDay.secondaryText,
                label: post.viewerHasLiked ? "Unlike" : "Like"
            ) {
                Task { await store.toggleLike(post) }
            }

            // Share is the system sheet, not something the server hears
            // about: what is being handed over is a link, and where it goes
            // afterwards is not ours to count.
            ShareLink(item: shareText) {
                actionLabel(
                    symbol: "square.and.arrow.up",
                    count: 0,
                    tint: timeOfDay.secondaryText
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")
        }
        .padding(.top, 2)
    }

    /// What leaves the app. A description rather than a URL: Repbase has no
    /// public web page for a post, and a link that opens nothing is worse
    /// than no link.
    private var shareText: String {
        let shown = post.displayed
        let who = shown.author.displayName
        if !shown.caption.isEmpty {
            return "\(who) on Rytivo: \(shown.caption)"
        }
        if let workout = shown.workout {
            return "\(who) trained \(workout.title) on Rytivo."
        }
        if let meal = shown.meal {
            return "\(who) logged \(meal.name) on Rytivo."
        }
        return "\(who) posted on Rytivo."
    }

    private func action(
        symbol: String,
        count: Int,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionLabel(symbol: symbol, count: count, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(label), \(count)" : label)
    }

    private func actionLabel(symbol: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.community(size: 14, weight: .medium))
            if count > 0 {
                Text(Self.compact(count))
                    .font(.community(size: 12, weight: .semibold))
                    .contentTransition(.numericText())
            }
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A tap target the whole width of its quarter, so the number is as
        // tappable as the icon and neither needs aiming for.
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.18), value: count)
    }

    /// 1.2k rather than 1,247. The exact figure is not what the reader is
    /// asking, and it pushes the next action off the row.
    static func compact(_ count: Int) -> String {
        if count < 1_000 { return "\(count)" }
        let thousands = Double(count) / 1_000
        if count < 10_000 {
            return String(format: "%.1fk", thousands)
                .replacingOccurrences(of: ".0k", with: "k")
        }
        return "\(Int(thousands.rounded()))k"
    }
}
