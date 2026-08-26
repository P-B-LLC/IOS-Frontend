//
//  SocialLinksEditorView.swift
//  IOS Frontend
//
//  The outbound accounts on a profile, edited.
//
//  Deliberately plain. The public profile draws these as a row of icons and
//  that design is settled; this is the back of it, where somebody adds a
//  platform, types a handle, and saves.
//
//  Nothing here decides what a valid link is. A handle or a full address both
//  go up as typed and the server answers with the canonical URL it stored --
//  writing the same rule again in Swift would be a second copy to drift, and
//  the copy in the app is the one that cannot be trusted.
//

import SwiftUI

struct SocialLinksEditorView: View {
    @Environment(SocialProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// One row per platform the person has chosen, in the order they will
    /// appear. Seeded from the profile the store already holds.
    @State private var drafts: [ProfileSocialLinkDraft] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var hasLoaded = false

    private var unusedPlatforms: [ProfileSocialLink.Platform] {
        let taken = Set(drafts.map(\.platform))
        return ProfileSocialLink.Platform.allCases.filter { !taken.contains($0) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Add the accounts you want on your profile. Paste a link, or just type your handle and we will work out the address.")
                        .font(.footnote)
                        .foregroundStyle(timeOfDay.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if drafts.isEmpty {
                        Text("No links yet.")
                            .font(.subheadline)
                            .foregroundStyle(timeOfDay.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                    } else {
                        ForEach($drafts) { $draft in
                            row($draft, timeOfDay: timeOfDay)
                        }
                    }

                    if !unusedPlatforms.isEmpty {
                        Menu {
                            ForEach(unusedPlatforms, id: \.self) { platform in
                                Button {
                                    drafts.append(
                                        ProfileSocialLinkDraft(platform: platform, value: "")
                                    )
                                } label: {
                                    Label(platform.title, systemImage: platform.systemImage)
                                }
                            }
                        } label: {
                            Label("Add a platform", systemImage: "plus.circle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(timeOfDay.accent)
                        }
                    }

                    // The server's own words. It knows which row was wrong and
                    // why, and paraphrasing that here would only be a worse
                    // version of the same sentence.
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(RepbaseDesign.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        save()
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving { ProgressView().controlSize(.small) }
                            Text("Save links")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EditorialPrimaryButtonStyle())
                    .disabled(isSaving)
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 16)
                .padding(.bottom, RepbaseDesign.bottomBarClearance)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Social links")
            .navigationBarTitleDisplayMode(.inline)
            .homeTimeScreen(timeOfDay)
        }
        .task {
            // Once. Re-seeding on every appearance would throw away an edit
            // the moment anything else refreshed the profile underneath.
            guard !hasLoaded else { return }
            hasLoaded = true
            drafts = (store.profile?.socialLinks ?? []).map {
                ProfileSocialLinkDraft(
                    platform: $0.platform,
                    value: $0.url.absoluteString
                )
            }
        }
    }

    private func row(
        _ draft: Binding<ProfileSocialLinkDraft>,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label(
                    draft.wrappedValue.platform.title,
                    systemImage: draft.wrappedValue.platform.systemImage
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(timeOfDay.accent)

                Spacer(minLength: 0)

                Button {
                    drafts.removeAll { $0.platform == draft.wrappedValue.platform }
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17))
                        .foregroundStyle(RepbaseDesign.danger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(draft.wrappedValue.platform.title)")
            }

            TextField(placeholder(for: draft.wrappedValue.platform), text: draft.value)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    timeOfDay.primaryText.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .padding(.vertical, 6)
    }

    private func placeholder(for platform: ProfileSocialLink.Platform) -> String {
        platform == .website ? "https://example.com" : "@yourhandle or a link"
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            // Blank rows are a platform somebody added and thought better of,
            // not an error to tell them about.
            let filled = drafts.filter {
                !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let saved = await store.saveSocialLinks(filled)
            isSaving = false
            if saved {
                // Adopt what the server stored, so a handle typed in becomes
                // the canonical URL on screen rather than staying as typed.
                drafts = (store.profile?.socialLinks ?? []).map {
                    ProfileSocialLinkDraft(
                        platform: $0.platform,
                        value: $0.url.absoluteString
                    )
                }
                dismiss()
            } else {
                errorMessage = store.errorMessage
            }
        }
    }
}
