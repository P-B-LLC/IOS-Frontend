//
//  PostModerationViews.swift
//  IOS Frontend
//
//  Reporting a post, and the list of people a reader has blocked.
//
//  Blocking itself lives on the post's own menu and acts on the tap, like
//  every other destructive control here. This file is the two screens that
//  cannot: choosing a reason, which is a question, and lifting a block, which
//  needs somewhere to see the blocks from.
//

import SwiftUI

struct CommentReportSheet: View {
    let comment: PostComment
    @Environment(SocialStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reason: PostReportReason = .other
    @State private var detail = ""
    @State private var sending = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("What happened?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(PostReportReason.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    TextField("Details (optional)", text: $detail, axis: .vertical)
                        .onChange(of: detail) { _, value in detail = String(value.prefix(500)) }
                }
                Section {
                    Text("Only moderators can read your report. It is not sent to the automated safety provider.")
                    Text("Safety contact: \(LegalDocuments.contactEmail)")
                    if let failure { Text(failure).foregroundStyle(.red) }
                    Button {
                        sending = true
                        failure = nil
                        Task {
                            let sent = await store.reportComment(comment, reason: reason, detail: detail)
                            sending = false
                            if sent { dismiss() }
                            else { failure = "The report was not confirmed. Please try again." }
                        }
                    } label: {
                        if sending { ProgressView() }
                        else { Text("Send report") }
                    }
                    .disabled(sending)
                }
            }
            .font(.community(.body))
            .navigationTitle("Report comment")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(sending) } }
        }
        .interactiveDismissDisabled(sending)
    }
}

/// The reasons, and the box for anything they do not cover.
struct PostReportSheet: View {
    let post: FeedPost
    let timeOfDay: HomeTimeOfDay

    @Environment(SocialStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var reason: PostReportReason?
    @State private var detail = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("What is wrong with this post?")
                        .font(.community(size: 22, weight: .bold))
                        .foregroundStyle(timeOfDay.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Only moderators see a report. \(post.displayed.author.displayName) is not told who sent it.")
                        .font(.community(.footnote))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        ForEach(PostReportReason.allCases) { option in
                            Button {
                                reason = option
                            } label: {
                                HStack(spacing: 12) {
                                    Image(
                                        systemName: reason == option
                                            ? "largecircle.fill.circle"
                                            : "circle"
                                    )
                                    .font(.community(size: 17))
                                    .foregroundStyle(
                                        reason == option
                                            ? timeOfDay.accent
                                            : timeOfDay.secondaryText.opacity(0.5)
                                    )

                                    Text(option.title)
                                        .font(.community(.subheadline))
                                        .foregroundStyle(timeOfDay.primaryText)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Asked for only where the list ran out. Making someone
                    // explain a plain "spam" would be a form where a tap does.
                    if reason?.invitesDetail == true {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What happened?")
                                .font(.community(.caption, weight: .semibold))
                                .foregroundStyle(timeOfDay.secondaryText)
                            TextField(
                                "Anything that helps a moderator",
                                text: $detail,
                                axis: .vertical
                            )
                            .lineLimit(3...6)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(
                                timeOfDay.primaryText.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                    }

                    Button {
                        send()
                    } label: {
                        HStack(spacing: 8) {
                            if isSending { ProgressView().controlSize(.small) }
                            Text("Send report")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EditorialPrimaryButtonStyle())
                    .disabled(reason == nil || isSending)
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func send() {
        guard let reason else { return }
        isSending = true
        Task {
            await store.report(post, reason: reason, detail: detail)
            // Closed either way. The feed says what happened, and holding the
            // sheet open over a report already sent invites a second one.
            dismiss()
        }
    }
}

/// Everyone this reader has blocked, and the way back.
///
/// Blocking acts on one tap with nothing to confirm, which is the rule here
/// and the right one — but a block with no way to lift it turns a misplaced
/// tap into something permanent. This is that way.
struct BlockedAccountsView: View {
    @Environment(SocialStore.self) private var store

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Blocked people cannot see your posts, and you cannot see theirs. Blocking also removes any following between you, which lifting a block does not put back.")
                    .font(.community(.footnote))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if store.isLoadingBlocks && store.blockedPeople.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if store.blockedPeople.isEmpty {
                    ContentUnavailableView(
                        "Nobody is blocked",
                        systemImage: "hand.raised",
                        description: Text("People you block from a post will appear here.")
                    )
                    .padding(.top, 30)
                } else {
                    ForEach(store.blockedPeople) { blocked in
                        HStack(spacing: 11) {
                            avatar(blocked.person, timeOfDay: timeOfDay)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(blocked.person.displayName)
                                    .font(.community(.subheadline, weight: .semibold))
                                    .foregroundStyle(timeOfDay.primaryText)
                                    .lineLimit(1)
                                Text("@\(blocked.person.username)")
                                    .font(.community(.caption2))
                                    .foregroundStyle(timeOfDay.secondaryText)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Button("Unblock") {
                                Task { await store.unblock(blocked) }
                            }
                            .font(.community(.caption, weight: .semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(timeOfDay.accent)
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 14)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Blocked accounts")
        .navigationBarTitleDisplayMode(.inline)
        .homeTimeScreen(timeOfDay)
        .task { await store.loadBlocks() }
    }

    private func avatar(_ person: PostAuthor, timeOfDay: HomeTimeOfDay) -> some View {
        Group {
            if let photo = person.photoURL, let url = URL(string: photo) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials(person, timeOfDay: timeOfDay)
                }
            } else {
                initials(person, timeOfDay: timeOfDay)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
    }

    private func initials(_ person: PostAuthor, timeOfDay: HomeTimeOfDay) -> some View {
        ZStack {
            Circle().fill(timeOfDay.accent.opacity(0.18))
            Text(person.initials)
                .font(.community(size: 12, weight: .bold))
                .foregroundStyle(timeOfDay.accent)
        }
    }
}
