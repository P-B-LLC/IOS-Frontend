//
//  FollowButton.swift
//  IOS Frontend
//
//  The follow button and the "Follows you" label, the same on every screen.
//

import SwiftUI

/// Follows, follows back, requests, or -- for someone already followed or
/// asked -- offers to undo it.
///
/// The button only ever describes the viewer's own side, so "Following" never
/// hides whether the follow is returned; that is the job of
/// `RelationshipBadge` beside it. Following is one tap. Undoing it is not:
/// "Following" and "Requested" open a confirmation, because one stray tap in a
/// list used to unfollow on the spot, and unfollowing a closed profile means
/// asking again and waiting to be let back in.
struct FollowButton: View {
    enum Size { case large, compact }

    let person: PostAuthor
    let relationship: FollowRelationship
    let viewerID: Int?
    var size: Size = .compact

    @Environment(SocialStore.self) private var social
    @State private var confirming = false

    private var isChanging: Bool { social.changingFollowFor.contains(person.id) }
    private var accent: Color { RepbasePalette.caramel }

    var body: some View {
        Button(action: tap) { label }
        .buttonStyle(.plain)
        .disabled(isChanging)
        .sensoryFeedback(trigger: relationship.action, Self.feedback)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(accessibilityHint)
        .confirmationDialog(dialogTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(leaveTitle, role: .destructive, action: leave)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(dialogMessage)
        }
    }

    /// A firm tap for following or asking, a light one for stepping back.
    nonisolated private static func feedback(_ old: FollowRelationship.Action, _ new: FollowRelationship.Action) -> SensoryFeedback? {
        switch new {
        case .following, .requested: return .success
        case .follow, .followBack, .request: return .impact(weight: .light)
        }
    }

    private var leaveTitle: LocalizedStringKey {
        relationship.action == .requested ? "Withdraw request" : "Unfollow"
    }

    private func leave() {
        Task { await social.setFollowing(false, user: person, viewerID: viewerID) }
    }

    private func tap() {
        switch relationship.action {
        case .follow, .followBack, .request:
            Task {
                await social.setFollowing(
                    true, user: person, viewerID: viewerID,
                    expectsRequest: relationship.action == .request
                )
            }
        case .following, .requested:
            confirming = true
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.community(size == .large ? .footnote : .caption2, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.community(size == .large ? .footnote : .caption, weight: .bold))
                .lineLimit(1)
            if relationship.action == .following {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(isProminent ? Color.white : Color.primary)
        .padding(.horizontal, size == .large ? 18 : 14)
        .frame(maxWidth: size == .large ? .infinity : nil, minHeight: size == .large ? 40 : 32)
        .background(background, in: Capsule())
        .overlay {
            if !isProminent { Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.2), value: relationship.action)
    }

    private var background: AnyShapeStyle {
        isProminent ? AnyShapeStyle(accent) : AnyShapeStyle(Color.primary.opacity(0.07))
    }

    private var isProminent: Bool {
        switch relationship.action {
        case .follow, .followBack, .request: true
        case .following, .requested: false
        }
    }

    private var title: LocalizedStringKey {
        switch relationship.action {
        case .follow: "Follow"
        case .followBack: "Follow back"
        case .request: "Request to follow"
        case .requested: "Requested"
        case .following: "Following"
        }
    }

    private var symbol: String {
        switch relationship.action {
        case .follow, .followBack: "person.badge.plus"
        case .request: "lock"
        case .requested: "clock"
        case .following: "checkmark"
        }
    }

    private var accessibilityTitle: String {
        switch relationship.action {
        case .follow: String(localized: "Follow \(person.displayName)", bundle: .app, locale: .app)
        case .followBack: String(localized: "Follow \(person.displayName) back", bundle: .app, locale: .app)
        case .request: String(localized: "Request to follow \(person.displayName)", bundle: .app, locale: .app)
        case .requested: String(localized: "Follow request sent to \(person.displayName)", bundle: .app, locale: .app)
        case .following: String(localized: "Following \(person.displayName)", bundle: .app, locale: .app)
        }
    }

    private var accessibilityHint: String {
        switch relationship.action {
        case .following: String(localized: "Offers to unfollow", bundle: .app, locale: .app)
        case .requested: String(localized: "Offers to withdraw your request", bundle: .app, locale: .app)
        case .request: String(localized: "Their profile is private. They will see your request.", bundle: .app, locale: .app)
        case .follow, .followBack: ""
        }
    }

    private var dialogTitle: String {
        relationship.action == .requested
            ? String(localized: "Withdraw your request to follow @\(person.username)?", bundle: .app, locale: .app)
            : String(localized: "Unfollow @\(person.username)?", bundle: .app, locale: .app)
    }

    private var dialogMessage: String {
        if relationship.action == .requested {
            return String(localized: "They won’t be told. You can ask again later.", bundle: .app, locale: .app)
        }
        if relationship.isPrivate {
            return String(localized: "Their profile is private, so following again means sending a new request.", bundle: .app, locale: .app)
        }
        if relationship.isMutual {
            return String(localized: "They’ll still follow you. You can follow them again at any time.", bundle: .app, locale: .app)
        }
        return String(localized: "You can follow them again at any time.", bundle: .app, locale: .app)
    }
}

/// What the other person's side of the relationship is, as a label: they
/// follow you, or you follow each other. Nothing when they do not, because
/// "Doesn't follow you" is not something anybody needs pointed out.
struct RelationshipBadge: View {
    let relationship: FollowRelationship

    var body: some View {
        if let badge = relationship.badge {
            Label {
                Text(badge == .mutual ? "You follow each other" : "Follows you")
            } icon: {
                Image(systemName: badge == .mutual ? "arrow.left.arrow.right" : "person.fill.checkmark")
            }
            .font(.community(.caption2, weight: .bold))
            .foregroundStyle(badge == .mutual ? RepbasePalette.caramel : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                (badge == .mutual ? RepbasePalette.caramel.opacity(0.12) : Color.primary.opacity(0.06)),
                in: Capsule()
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .accessibilityElement(children: .combine)
        }
    }
}
