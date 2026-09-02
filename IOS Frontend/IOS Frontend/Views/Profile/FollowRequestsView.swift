//
//  FollowRequestsView.swift
//  IOS Frontend
//
//  The people asking to follow a closed profile.
//
//  Only reachable, and only useful, while a profile is closed: an open one is
//  followed without asking, so nothing ever arrives here.
//

import SwiftUI

struct FollowRequestsView: View {
    @Environment(SocialStore.self) private var social

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("People who want to follow you. Approving lets them see your profile and your posts.")
                    .font(.community(.footnote))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if social.followRequests.isEmpty {
                    Text("No requests waiting.")
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(social.followRequests) { request in
                            row(request, timeOfDay: timeOfDay)
                            if request.id != social.followRequests.last?.id {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                }

                if let error = social.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.community(.footnote))
                        .foregroundStyle(RepbaseDesign.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 16)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Follow requests")
        .navigationBarTitleDisplayMode(.inline)
        .homeTimeScreen(timeOfDay)
        .task { await social.loadFollowRequests() }
    }

    private func row(
        _ request: FollowRequestSummary,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        // Answering is one tap with nothing to confirm, like the rest of this
        // app -- but the row leaves either way, so the tap is visible in what
        // happens next rather than in a dialog before it.
        let busy = social.answeringRequests.contains(request.id)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.displayName)
                    .font(.community(.subheadline, weight: .semibold))
                    .foregroundStyle(timeOfDay.primaryText)
                    .lineLimit(1)
                Text("@\(request.username)")
                    .font(.community(.caption))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Decline") {
                Task { await social.answerFollowRequest(request, approve: false) }
            }
            .font(.community(.footnote, weight: .semibold))
            .foregroundStyle(timeOfDay.secondaryText)
            .buttonStyle(.plain)
            .disabled(busy)

            Button("Approve") {
                Task { await social.answerFollowRequest(request, approve: true) }
            }
            .font(.community(.footnote, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(timeOfDay.accent, in: Capsule())
            .buttonStyle(.plain)
            .disabled(busy)
        }
        .padding(.vertical, 12)
        .opacity(busy ? 0.5 : 1)
    }
}
