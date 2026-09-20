//
//  NotificationsView.swift
//  IOS Frontend
//
//  What other people have done: follows, requests, likes, reposts and replies.
//
//  The inbox remains authoritative whether remote alerts are enabled or not.
//  A push tap may reach this view before the account stores finish connecting.
//

import SwiftUI

struct NotificationsView: View {
    @Environment(SocialStore.self) private var social
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading || !social.isConnected {
                    ProgressView("Loading activity…").padding(.vertical, 18)
                } else if loadFailed {
                    Button("Couldn't load activity. Retry") { Task { await refreshInbox() } }
                        .padding(.vertical, 18)
                } else if social.notifications.isEmpty {
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
        .task(id: social.isConnected) { await refreshInbox() }
        .refreshable { await refreshInbox() }
    }

    private func refreshInbox() async {
        guard social.isConnected, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let loaded = await social.loadNotifications()
        guard !Task.isCancelled else { return }
        loadFailed = !loaded
        if loaded { await social.markNotificationsRead() }
    }

    private func row(
        _ notification: SocialNotification,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        NavigationLink {
            PersonProfileView(userID: notification.actorID)
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
                    (
                        Text(notification.actorName)
                            .font(.community(.subheadline, weight: .semibold))
                        + Text(" \(notification.summary)")
                            .font(.community(.subheadline))
                    )
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
}
