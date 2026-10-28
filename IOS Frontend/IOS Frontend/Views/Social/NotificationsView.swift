//
//  NotificationsView.swift
//  IOS Frontend
//
//  What other people have done: follows, requests, likes, reposts and replies.
//
//  A page rather than a stream of alerts, and that is a constraint being
//  honest about itself. Anything another person does happens on the server,
//  and reaching a closed phone from there needs a push these builds cannot
//  send -- no Apple Developer membership behind them, no entitlement in them.
//  So this is read when it is opened. The reminders that *can* arrive on their
//  own are the ones the device schedules for itself, which is a different
//  thing entirely and lives in NotificationScheduler.
//

import SwiftUI

struct NotificationsView: View {
    @Environment(SocialStore.self) private var social

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if social.notifications.isEmpty {
                    Text("Nothing yet. Follows, likes, reposts and replies land here.")
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 18)
                } else {
                    ForEach(social.notifications) { notification in
                        row(notification, timeOfDay: timeOfDay)
                        Divider().opacity(0.45)
                    }
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .homeTimeScreen(timeOfDay)
        .task {
            await social.loadNotifications()
            // Opening the page is what seeing them means, so the badge clears
            // here rather than needing a button that says "I have read these".
            await social.markNotificationsRead()
        }
    }

    private func row(
        _ notification: SocialNotification,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        NavigationLink {
            if notification.kind == .moderationRejected, let postID = notification.postID {
                PostDetailView(postID: postID)
            } else {
                PersonProfileView(userID: notification.actorID)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notification.symbol)
                    .font(.community(.subheadline, weight: .semibold))
                    .foregroundStyle(timeOfDay.accent)
                    .frame(width: 34, height: 34)
                    .background(timeOfDay.accent.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    // The name and what they did in one line, so a page of
                    // these reads as sentences rather than as a table.
                    headline(notification)
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.primaryText)
                        .multilineTextAlignment(.leading)

                    // Quoted, because "commented on your post" without the
                    // comment is a notification that makes you go and look.
                    if let body = notification.commentBody, !body.isEmpty {
                        Text("\u{201C}\(body)\u{201D}")
                            .font(.community(.footnote))
                            .foregroundStyle(timeOfDay.secondaryText)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 6)

                if !notification.isRead {
                    Circle()
                        .fill(timeOfDay.accent)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `SocialNotification.summary` with the name set heavier. The name is
    /// interpolated as styled text rather than joined on the front, so each
    /// sentence is still translated whole -- the keys are the same ones.
    private func headline(_ notification: SocialNotification) -> Text {
        let name = Text(notification.actorName)
            .font(.community(.subheadline, weight: .semibold))
        switch notification.kind {
        case .follow: return Text("\(name) started following you")
        case .followRequest: return Text("\(name) asked to follow you")
        case .followApproved: return Text("\(name) accepted your follow request")
        case .like: return Text("\(name) liked your post")
        case .repost: return Text("\(name) reposted your post")
        case .comment: return Text("\(name) commented on your post")
        case .moderationRejected:
            return Text(
                "\(name) did not publish your post after review. You can check it on your profile or contact support.",
                comment: "The placeholder is the app's name, Rytivo"
            )
        case .unknown: return Text("\(name) did something")
        }
    }
}
