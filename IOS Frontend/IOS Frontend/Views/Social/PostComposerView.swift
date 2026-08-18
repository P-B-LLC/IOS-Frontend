//
//  PostComposerView.swift
//  IOS Frontend
//
//  Writing a post. Pick something already recorded — a finished session, a
//  logged meal, a calendar entry — add a caption, and choose who sees it.
//
//  Only the reference goes out. The server reads the source and builds the
//  snapshot from it, so what a post claims was done is never the phone's to
//  decide, and this screen never gathers contents to send.
//

import Foundation
import SwiftUI

struct PostComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SocialStore.self) private var social
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(FoodTrackingStore.self) private var foodStore
    @Environment(PlannerStore.self) private var plannerStore

    @State private var source: PostSource = .workout
    @State private var selection: PostCandidate?
    @State private var caption = ""
    @State private var visibility: PostVisibility = .publicToAll

    /// The contract's cap. Enforced here so a long caption is stopped as it is
    /// typed rather than by a 400 with nothing on screen to explain it.
    private static let captionLimit = 300

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            screen(timeOfDay: HomeTimeOfDay(date: context.date))
        }
    }

    private func screen(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 0) {
            EditorialFormHeader(
                title: "New Post",
                leadingAction: .cancel,
                saveTitle: "Post",
                canSave: canPost,
                onDismiss: { dismiss() },
                onSave: { post() }
            )
            .padding(.horizontal, RepbaseDesign.pageInset)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !social.isConnected {
                        notice(
                            "Connect to Repbase to post.",
                            timeOfDay: timeOfDay
                        )
                    }
                    if let message = social.errorMessage {
                        notice(message, timeOfDay: timeOfDay)
                    }

                    sourcePicker(timeOfDay: timeOfDay)
                    candidateSection(timeOfDay: timeOfDay)
                    captionSection(timeOfDay: timeOfDay)
                    visibilitySection(timeOfDay: timeOfDay)
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 4)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .homeTimeScreen(timeOfDay)
        .overlay {
            if social.isPosting {
                postingOverlay(timeOfDay: timeOfDay)
            }
        }
        .task {
            // An error left over from the feed is not about this sheet.
            social.clearError()
            // Meals and calendar entries are already held by their stores;
            // only finished sessions have to be asked for.
            await workoutStore.loadPostableSessions()
        }
    }

    // MARK: - Choosing a source

    private func sourcePicker(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 7) {
            ForEach(PostSource.allCases) { item in
                Button {
                    select(item)
                } label: {
                    sourceChip(item, timeOfDay: timeOfDay)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item == source ? [.isSelected] : [])
            }
        }
    }

    private func sourceChip(
        _ item: PostSource,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        let isSelected = item == source
        return VStack(spacing: 5) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .semibold))
            Text(item.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isSelected ? timeOfDay.accent : timeOfDay.canvasSecondaryText)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(
            isSelected ? timeOfDay.accent.opacity(0.11) : Color.clear,
            in: RoundedRectangle(cornerRadius: RepbaseDesign.controlRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RepbaseDesign.controlRadius)
                .strokeBorder(
                    isSelected ? timeOfDay.accent.opacity(0.55) : timeOfDay.canvasBorder,
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
    }

    private func select(_ item: PostSource) {
        guard source != item else { return }
        source = item
        // A selection belongs to the source it came from; carrying one across
        // would post a meal while the picker showed workouts.
        selection = nil
    }

    // MARK: - Choosing what to post

    private func candidateSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            EditorialSectionTitle(
                title: "Choose something",
                detail: "A post is built from what you have already recorded."
            )

            if source == .workout && workoutStore.isLoadingPostableSessions {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
            } else if candidates.isEmpty {
                emptyRow(timeOfDay: timeOfDay)
            } else {
                EditorialRuleGroup {
                    ForEach(candidates) { candidate in
                        candidateRow(
                            candidate,
                            timeOfDay: timeOfDay,
                            isLast: candidate.id == candidates.last?.id
                        )
                    }
                }
            }
        }
    }

    private func candidateRow(
        _ candidate: PostCandidate,
        timeOfDay: HomeTimeOfDay,
        isLast: Bool
    ) -> some View {
        let isSelected = selection?.id == candidate.id
        return Button {
            // Tapping the chosen row again clears it, so a choice can be
            // taken back without leaving the sheet.
            selection = isSelected ? nil : candidate
        } label: {
            EditorialRuleRow(showsDivider: !isLast) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .multilineTextAlignment(.leading)
                    Text(candidate.subtitle)
                        .font(.caption)
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(
                        isSelected
                            ? timeOfDay.accent
                            : timeOfDay.canvasSecondaryText.opacity(0.38)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func emptyRow(timeOfDay: HomeTimeOfDay) -> some View {
        Text(source.emptyMessage)
            .font(.subheadline)
            .foregroundStyle(timeOfDay.canvasSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 22)
    }

    // MARK: - Caption

    private func captionSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            EditorialSectionTitle(title: "Caption", detail: "Optional.")

            EditorialRuleGroup {
                EditorialRuleRow(showsDivider: false) {
                    TextField(
                        "Say something about it",
                        text: $caption,
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                    .font(.subheadline)
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                    .textInputAutocapitalization(.sentences)
                    .onChange(of: caption) { _, value in
                        if value.count > Self.captionLimit {
                            caption = String(value.prefix(Self.captionLimit))
                        }
                    }
                }
            }

            Text("\(caption.count)/\(Self.captionLimit)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Visibility

    private func visibilitySection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            EditorialSectionTitle(title: "Who can see it")

            EditorialRuleGroup {
                ForEach(PostVisibility.allCases) { level in
                    visibilityRow(
                        level,
                        timeOfDay: timeOfDay,
                        isLast: level.id == PostVisibility.allCases.last?.id
                    )
                }
            }
        }
    }

    private func visibilityRow(
        _ level: PostVisibility,
        timeOfDay: HomeTimeOfDay,
        isLast: Bool
    ) -> some View {
        let isSelected = level == visibility
        return Button {
            visibility = level
        } label: {
            EditorialRuleRow(showsDivider: !isLast) {
                Image(systemName: level.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(timeOfDay.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                    Text(level.explanation)
                        .font(.caption)
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(
                        isSelected
                            ? timeOfDay.accent
                            : timeOfDay.canvasSecondaryText.opacity(0.38)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Pieces

    private func notice(
        _ message: String,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(timeOfDay.accent)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(timeOfDay.canvasSecondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            timeOfDay.accent.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func postingOverlay(timeOfDay: HomeTimeOfDay) -> some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            ProgressView("Posting…")
                .padding(18)
                .foregroundStyle(timeOfDay.primaryText)
                .background(
                    timeOfDay.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 16)
                )
        }
    }

    // MARK: - Sending

    private var canPost: Bool {
        selection != nil && social.isConnected && !social.isPosting
    }

    private func post() {
        guard let selection else { return }
        Task {
            let sent = await social.post(
                kind: selection.kind,
                sourceID: selection.sourceID,
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                visibility: visibility
            )
            // Left open when it failed, so the error is read beside the post it
            // belongs to and the caption is not lost.
            if sent { dismiss() }
        }
    }

    // MARK: - What there is to post

    private var candidates: [PostCandidate] {
        switch source {
        case .workout: workoutCandidates
        case .meal: mealCandidates
        case .planner: plannerCandidates
        }
    }

    private var workoutCandidates: [PostCandidate] {
        workoutStore.postableSessions.map { session in
            PostCandidate(
                kind: .workout,
                sourceID: session.sessionID,
                title: session.workoutName,
                subtitle: Self.sessionSubtitle(session)
            )
        }
    }

    private var mealCandidates: [PostCandidate] {
        foodStore.days
            .sorted { $0.key > $1.key }
            .flatMap { day -> [PostCandidate] in
                day.value.compactMap { meal -> PostCandidate? in
                    // An empty slot is a meal not eaten yet. Offering it would
                    // post a name and nothing else.
                    guard let serverID = meal.serverID, !meal.entries.isEmpty else {
                        return nil
                    }
                    let calories = meal.totalNutrition.calories.nutritionText
                    return PostCandidate(
                        kind: .meal,
                        sourceID: serverID,
                        title: meal.name,
                        subtitle: "\(PostDateText.label(forKey: day.key)) · \(calories) kcal"
                    )
                }
            }
    }

    private var plannerCandidates: [PostCandidate] {
        plannerStore.entriesByDate
            .sorted { $0.key > $1.key }
            .flatMap { day -> [PostCandidate] in
                day.value.compactMap { entry -> PostCandidate? in
                    // A draft that never reached the server has no id to post.
                    guard let serverID = entry.serverID else { return nil }
                    return PostCandidate(
                        kind: .planner,
                        sourceID: serverID,
                        title: entry.title,
                        subtitle: Self.plannerSubtitle(entry, dayKey: day.key)
                    )
                }
            }
    }

    private static func sessionSubtitle(_ session: PostableSession) -> String {
        var parts = [PostDateText.label(for: session.performedAt)]
        if let distance = session.routeDistanceKilometers, distance > 0 {
            parts.append(String(format: "%.1f km", distance))
        } else if let seconds = session.durationSeconds, seconds >= 60 {
            parts.append("\(Int(seconds / 60)) min")
        }
        return parts.joined(separator: " · ")
    }

    private static func plannerSubtitle(
        _ entry: PlannerEntry,
        dayKey: String
    ) -> String {
        var parts = [PostDateText.label(forKey: dayKey)]
        if let time = entry.displayTime { parts.append(time) }
        parts.append(entry.kind.title)
        if entry.isComplete { parts.append("Done") }
        return parts.joined(separator: " · ")
    }
}

/// Dates for the picker's rows.
///
/// A day key is a literal `YYYY-MM-DD`, so it is read and written back in the
/// current calendar rather than UTC: parsed as midnight elsewhere, a date can
/// come out a day early on screen.
private enum PostDateText {
    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func label(forKey key: String) -> String {
        guard let date = dayParser.date(from: key) else { return key }
        return label(for: date)
    }

    static func label(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
