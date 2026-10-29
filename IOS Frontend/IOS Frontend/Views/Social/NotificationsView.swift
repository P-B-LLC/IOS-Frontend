import SwiftUI

/// One card per post across dates; people and moderation notices stay separate.
struct NotificationsView: View {
    @Environment(SocialStore.self) private var social
    private let theme = HomeTimeOfDay.current

    var body: some View {
        let sections = NotificationDateSection.sections(social.notificationGroups)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your people. Your progress.")
                        .font(.community(.subheadline)).foregroundStyle(theme.secondaryText)
                    Text("All activity").font(.community(.callout)).accessibilityAddTraits(.isHeader)
                }
                .padding(.bottom, 8)
                if let error = social.notificationsError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Activity could not be loaded").font(.community(.headline))
                        Text(error).font(.community(.footnote))
                        Button("Retry") { Task { await social.loadNotifications() } }.buttonStyle(.bordered)
                    }.padding(.vertical, 12)
                }
                if social.isLoadingNotifications && !social.hasLoadedNotifications {
                    ProgressView("Loading activity…").frame(maxWidth: .infinity).padding(.vertical, 32)
                } else if social.hasLoadedNotifications && social.notifications.isEmpty && social.notificationsError == nil {
                    ContentUnavailableView(
                        "Nothing yet. Follows, likes, reposts and replies land here.",
                        systemImage: "bell", description: Text("New activity will appear here.")
                    )
                }
                ForEach(sections) { section in
                    HStack {
                        Text(section.title).font(.community(.headline)).accessibilityAddTraits(.isHeader)
                        Spacer()
                        if section.id == sections.first?.id {
                            Text("Latest first").font(.community(.caption)).foregroundStyle(theme.secondaryText)
                        }
                    }.padding(.top, 4)
                    ForEach(section.groups) { group in
                        NotificationActivityCard(group: group)
                            // Lazy-stack construction isn't proof that a card was seen.
                            .modifier(NotificationReadVisibility(ids: group.unreadIDs))
                    }
                }
                if social.notificationReadError != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Activity could not be marked as read.").font(.community(.footnote))
                        Button("Retry marking as read") {
                            Task { await social.retryNotificationReads() }
                        }.buttonStyle(.bordered)
                    }.padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Notifications").navigationBarTitleDisplayMode(.large)
        .homeTimeScreen(theme)
        .refreshable { await social.loadNotifications() }
        .task(id: social.isConnected) {
            guard social.isConnected else { return }
            await social.loadNotifications()
        }
    }
}

private struct NotificationDateSection: Identifiable {
    let id: String
    let title: String
    var groups: [SocialNotificationGroup]

    static func sections(_ groups: [SocialNotificationGroup]) -> [Self] {
        var sections: [Self] = []
        let calendar = Calendar.current
        for group in groups {
            let key: String
            let title: String
            if let date = group.createdAt, calendar.isDateInToday(date) {
                key = "today"
                title = String(localized: "Today", bundle: .app, locale: .app)
            } else if let date = group.createdAt, calendar.isDateInYesterday(date) {
                key = "yesterday"
                title = String(localized: "Yesterday", bundle: .app, locale: .app)
            } else {
                key = "earlier"
                title = String(localized: "Earlier", bundle: .app, locale: .app)
            }
            if let index = sections.firstIndex(where: { $0.id == key }) {
                sections[index].groups.append(group)
            } else {
                sections.append(Self(id: key, title: title, groups: [group]))
            }
        }
        return sections
    }
}

private struct NotificationActivityCard: View {
    let group: SocialNotificationGroup
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    private let theme = HomeTimeOfDay.current

    var body: some View {
        HStack(spacing: 12) {
            avatarLink
            NavigationLink { destination } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(.community(size: 14))
                        .foregroundStyle(theme.primaryText).fixedSize(horizontal: false, vertical: true)
                    if group.isPostActivity {
                        Text(actionCounts).font(.community(size: 11.5, weight: .semibold))
                            .foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                    } else if !group.latest.actorUsername.isEmpty && group.latest.kind != .moderationRejected {
                        Text(verbatim: "@\(group.latest.actorUsername)")
                            .font(.community(.caption)).foregroundStyle(theme.secondaryText)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if !group.isRead {
                            Circle().fill(theme.accent).frame(width: 5, height: 5).accessibilityLabel("Unread")
                        }
                        Text(context).font(.community(size: 10.5, weight: .semibold))
                            .foregroundStyle(group.isRead ? theme.secondaryText : theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(group.isPostActivity ? Text("View activity") : Text("View profile"))
            if !dynamicTypeSize.isAccessibilitySize { previewLink }
        }
        .padding(.horizontal, 10).padding(.vertical, group.isPostActivity ? 10 : 8)
        .frame(maxWidth: .infinity, minHeight: group.isPostActivity ? 96 : 88)
        .background(group.isRead ? theme.surface : theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(theme.accent.opacity(contrast == .increased ? 1 : 0.5), lineWidth: 1.25)
        }
        // No fixed card height: large text and longer translations must grow.
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var destination: some View {
        if group.isPostActivity, let postID = group.postID {
            NotificationPostActivityView(postID: postID)
        } else if group.latest.kind == .moderationRejected, let postID = group.latest.postID {
            PostDetailView(postID: postID)
        } else { PersonProfileView(userID: group.latest.actorID) }
    }

    @ViewBuilder private var avatarLink: some View {
        if group.actors.count > 1, let postID = group.postID {
            NavigationLink { NotificationPostActivityView(postID: postID) } label: {
                NotificationAvatarStack(actors: group.actors)
            }.buttonStyle(.plain).accessibilityLabel("View activity")
        } else if group.latest.kind == .moderationRejected || group.latest.kind == .unknown {
            Image(systemName: group.latest.symbol).font(.community(.title3))
                .foregroundStyle(theme.accent).frame(width: 48, height: 48).accessibilityHidden(true)
        } else {
            NavigationLink { PersonProfileView(userID: group.latest.actorID) } label: {
                NotificationAvatarStack(actors: [group.latest])
            }.buttonStyle(.plain).accessibilityLabel(Text(group.latest.actorName)).accessibilityHint("View profile")
        }
    }

    @ViewBuilder private var previewLink: some View {
        if group.isPostActivity, let postID = group.postID {
            NavigationLink { PostDetailView(postID: postID) } label: {
                NotificationPostThumbnail(preview: group.preview)
            }.buttonStyle(.plain).accessibilityLabel("Open post")
        } else if group.latest.kind != .moderationRejected && group.latest.kind != .unknown {
            NavigationLink { PersonProfileView(userID: group.latest.actorID) } label: {
                VStack(spacing: 3) {
                    Image(systemName: "person.crop.circle").font(.community(.title3))
                    Text("Profile").font(.community(size: 10, weight: .semibold))
                }
                .foregroundStyle(theme.accent).frame(width: 52, height: 52)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.accent))
            }.buttonStyle(.plain).accessibilityLabel("View profile")
        }
    }

    private var headline: String {
        guard group.isPostActivity, group.notifications.count > 1 else { return group.latest.summary }
        let people: String
        let actors = group.actors
        if actors.count > 2 {
            people = String(localized: "\(actors[0].actorName), \(actors[1].actorName) and \(actors.count - 2) others", bundle: .app, locale: .app)
        } else if actors.count == 2 {
            people = String(localized: "\(actors[0].actorName) and \(actors[1].actorName)", bundle: .app, locale: .app)
        } else { people = group.latest.actorName }
        // Replies may concern someone else's post, so don't invent ownership.
        return String(localized: "\(people) interacted with a post", bundle: .app, locale: .app)
    }

    private var actionCounts: String {
        var parts: [String] = []
        if group.likes > 0 { parts.append(String(localized: "\(group.likes) likes", bundle: .app, locale: .app)) }
        if group.comments > 0 { parts.append(String(localized: "\(group.comments) comments", bundle: .app, locale: .app)) }
        if group.reposts > 0 { parts.append(String(localized: "\(group.reposts) reposts", bundle: .app, locale: .app)) }
        return parts.joined(separator: " · ")
    }

    private var context: String {
        [group.preview?.title, NotificationTime.label(group.createdAt)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct NotificationAvatarStack: View {
    let actors: [SocialNotification]
    private let theme = HomeTimeOfDay.current
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let first = actors.first {
                NotificationActorAvatar(actor: first, size: actors.count > 1 ? 36 : 40)
            }
            if actors.count > 1 {
                NotificationActorAvatar(actor: actors[1], size: 36)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            } else if let actor = actors.first, [.follow, .followRequest, .followApproved].contains(actor.kind) {
                Image(systemName: actor.symbol).font(.community(size: 10, weight: .semibold))
                    .foregroundStyle(.white).frame(width: 18, height: 18)
                    .background(theme.accent, in: Circle())
                    .overlay(Circle().strokeBorder(theme.surface, lineWidth: 2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }.frame(width: 48, height: 48).accessibilityHidden(true)
    }
}

private struct NotificationActorAvatar: View {
    let actor: SocialNotification
    let size: CGFloat
    private let theme = HomeTimeOfDay.current
    var body: some View {
        Group {
            if let value = actor.actorPhotoURL, let url = URL(string: value), url.scheme == "https" {
                RemoteImage(url: url, maxPixel: 144) { fallback } failure: { fallback }.scaledToFill()
            } else { fallback }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().strokeBorder(theme.surface, lineWidth: 2))
    }
    private var fallback: some View {
        let initials = actor.actorName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return Text(verbatim: initials).font(.community(size: 12, weight: .semibold))
            .foregroundStyle(theme.primaryText).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.accent.opacity(0.12))
    }
}

private struct NotificationPostThumbnail: View {
    let preview: SocialNotificationPostPreview?
    private let theme = HomeTimeOfDay.current
    var body: some View {
        Group {
            if let value = preview?.thumbnailURL, let url = URL(string: value), url.scheme == "https" {
                RemoteImage(url: url, maxPixel: 180) { fallback } failure: { fallback }.scaledToFill()
                    .overlay(alignment: .bottomTrailing) {
                        if preview?.mediaKind == "video" {
                            Image(systemName: "play.fill").font(.community(size: 10)).foregroundStyle(.white)
                                .padding(5).background(.black.opacity(0.65), in: Circle()).padding(3)
                        }
                    }
            } else { fallback }
        }.frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
    }
    private var fallback: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.community(.title3))
            Text(label).font(.community(size: 9, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(preview == nil ? theme.secondaryText : .white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(preview == nil ? theme.surfaceRaised : theme.ink)
    }
    private var symbol: String {
        guard let preview else { return "photo" }
        if preview.mediaKind == "video" { return "play.rectangle" }
        switch preview.kind {
        case "workout": return "dumbbell"
        case "meal": return "fork.knife"
        default: return "text.bubble"
        }
    }
    private var label: String {
        guard let preview else { return String(localized: "Post", bundle: .app, locale: .app) }
        if preview.mediaKind == "video" { return String(localized: "Video", bundle: .app, locale: .app) }
        switch preview.kind {
        case "workout": return String(localized: "Workout", bundle: .app, locale: .app)
        case "meal": return String(localized: "Meal", bundle: .app, locale: .app)
        default: return String(localized: "Post", bundle: .app, locale: .app)
        }
    }
}

/// Body/stacked-avatar taps reveal who did what; preview taps open the post.
private struct NotificationPostActivityView: View {
    let postID: Int
    @Environment(SocialStore.self) private var social
    private let theme = HomeTimeOfDay.current
    private var group: SocialNotificationGroup? {
        social.notificationGroups.first { $0.isPostActivity && $0.postID == postID }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let group {
                    NavigationLink { PostDetailView(postID: postID) } label: {
                        HStack(spacing: 12) {
                            NotificationPostThumbnail(preview: group.preview)
                            VStack(alignment: .leading, spacing: 4) {
                                if let title = group.preview?.title, !title.isEmpty {
                                    Text(title).foregroundStyle(theme.primaryText)
                                }
                                Label("Open post", systemImage: "arrow.right").foregroundStyle(theme.accent)
                            }.font(.community(.subheadline, weight: .semibold))
                            Spacer(minLength: 0)
                        }
                        .padding(12).background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.accent.opacity(0.5)))
                    }.buttonStyle(.plain)
                    ForEach(group.notifications) { notification in
                        HStack(alignment: .top, spacing: 12) {
                            NavigationLink { PersonProfileView(userID: notification.actorID) } label: {
                                NotificationActorAvatar(actor: notification, size: 44)
                            }.buttonStyle(.plain).accessibilityLabel(Text(notification.actorName)).accessibilityHint("View profile")
                            VStack(alignment: .leading, spacing: 6) {
                                Text(notification.summary).font(.community(.subheadline))
                                if let body = notification.commentBody, !body.isEmpty {
                                    Text(body).font(.community(.footnote)).foregroundStyle(theme.secondaryText)
                                }
                                if let date = NotificationTime.label(notification.createdAt) {
                                    Text(date).font(.community(.caption2)).foregroundStyle(theme.secondaryText)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            Image(systemName: notification.symbol).foregroundStyle(theme.accent).accessibilityHidden(true)
                        }.padding(.vertical, 6)
                        .modifier(NotificationReadVisibility(ids: notification.isRead ? [] : [notification.id]))
                    }
                } else {
                    Text("Activity is no longer available.").font(.community(.subheadline)).foregroundStyle(theme.secondaryText)
                }
                if let error = social.notificationsError {
                    Text(error).font(.community(.footnote)).foregroundStyle(theme.secondaryText)
                    Button("Retry") { Task { await social.loadNotifications() } }.buttonStyle(.bordered)
                }
                if social.notificationReadError != nil {
                    Text("Activity could not be marked as read.").font(.community(.footnote))
                    Button("Retry marking as read") {
                        Task { await social.retryNotificationReads() }
                    }.buttonStyle(.bordered)
                }
            }.padding(16).padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .navigationTitle("Post activity").navigationBarTitleDisplayMode(.inline).homeTimeScreen(theme)
        .refreshable { await social.loadNotifications() }
    }
}

private struct NotificationReadVisibility: ViewModifier {
    let ids: [Int]
    @Environment(SocialStore.self) private var social
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onScrollVisibilityChange(threshold: 0.5) { visible in
                isVisible = visible
                if visible { markVisible() }
            }
            .onChange(of: ids) { _, _ in
                // A refreshed group can gain an event without moving on screen.
                if isVisible { markVisible() }
            }
    }

    private func markVisible() {
        guard !ids.isEmpty else { return }
        Task { await social.markNotificationsRead(ids: ids) }
    }
}

private enum NotificationTime {
    static func label(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .app
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
