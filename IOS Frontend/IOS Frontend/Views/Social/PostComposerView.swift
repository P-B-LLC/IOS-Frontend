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
import PhotosUI
import SwiftUI

struct PostComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SocialStore.self) private var social
    @Environment(WorkoutStore.self) private var workoutStore
    @Environment(FoodTrackingStore.self) private var foodStore
    @Environment(PlannerStore.self) private var plannerStore

    @State private var source: PostSource = .workout
    @State private var selection: PostCandidate?
    /// The day the list is showing. Starts on the newest day that has anything
    /// rather than on today: opening onto an empty list because nobody trained
    /// this morning reads as "there is nothing to post".
    @State private var selectedDay = Date()
    @State private var didChooseOpeningDay = false
    @State private var caption = ""
    @State private var visibility: PostVisibility = .publicToAll
    /// Whether the numbers lifted go out with the workout. On by default:
    /// somebody who says nothing has posted a workout, and one without its
    /// numbers is the unusual case.
    @State private var showsWeights = true
    @State private var pickedPhoto: PhotosPickerItem?
    /// The chosen picture, already encoded. Held as bytes as well so the sheet
    /// can show what is about to be posted.
    @State private var photoData: Data?
    @State private var photoContentType: String?
    @State private var photoError: String?

    /// Set when the sheet was opened from a particular thing's page, which is
    /// then the only thing it can post. Nil when opened from the feed, where
    /// choosing what to post is the first thing the sheet asks.
    private let fixedSubject: String?
    /// Set when the sheet was opened from one feature's own page, so it offers
    /// that feature's things and does not ask which feature first.
    private let lockedSource: PostSource?

    /// The contract's cap. Enforced here so a long caption is stopped as it is
    /// typed rather than by a 400 with nothing on screen to explain it.
    private static let captionLimit = 300

    /// Opened from the feed: nothing chosen yet, and anything may be posted.
    init() {
        fixedSubject = nil
        lockedSource = nil
    }

    /// Opened from one feature's page. The page already says what kind of thing
    /// is being posted, so the sheet goes straight to choosing which one.
    init(source: PostSource) {
        fixedSubject = nil
        lockedSource = source
        _source = State(initialValue: source)
    }

    /// Opened from the page of the thing being shared, which already knows
    /// what it is. One composer serves both doors rather than two screens
    /// drifting apart over the same request.
    init(kind: PostKind, sourceID: Int, subject: String) {
        fixedSubject = subject
        lockedSource = nil
        _selection = State(
            initialValue: PostCandidate(
                kind: kind,
                sourceID: sourceID,
                title: subject,
                subtitle: ""
            )
        )
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            screen(timeOfDay: HomeTimeOfDay(date: context.date))
        }
    }

    private func screen(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 0) {
            EditorialFormHeader(
                title: composerTitle,
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

                    composerIntroduction(timeOfDay: timeOfDay)

                    if let fixedSubject {
                        subjectSection(fixedSubject, timeOfDay: timeOfDay)
                    } else {
                        // Asking which feature would be asking a question the
                        // page it was opened from has already answered.
                        if lockedSource == nil {
                            sourcePicker(timeOfDay: timeOfDay)
                        }
                        candidateSection(timeOfDay: timeOfDay)
                    }
                    photoSection(timeOfDay: timeOfDay)
                    captionSection(timeOfDay: timeOfDay)
                    if source == .workout {
                        weightsSection(timeOfDay: timeOfDay)
                    }
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
            // Nothing to choose from when the caller already chose, so the
            // pages of sessions are not worth reading.
            guard fixedSubject == nil, lockedSource == nil || lockedSource == .workout else { return }
            // Meals and calendar entries are already held by their stores;
            // only finished sessions have to be asked for.
            await workoutStore.loadPostableSessions()
            // After the fetch, not before: choosing from an empty list would
            // always land on today.
            chooseOpeningDayIfNeeded()
        }
        .onAppear {
            // Meals need no fetch, so their opening day can be chosen at once.
            if source == .meal { chooseOpeningDayIfNeeded() }
        }
        .onChange(of: source) {
            // A different kind has different days worth opening on.
            didChooseOpeningDay = false
            selection = nil
            chooseOpeningDayIfNeeded()
        }
    }

    private func composerIntroduction(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source == .meal ? "SHARE FOOD" : source == .workout ? "SHARE WORKOUT" : "SHARE YOUR DAY")
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(timeOfDay.accent)
            Text(source == .meal ? "Tell the story of this meal." : source == .workout ? "Share the work." : "Share the moment.")
                .font(.title.weight(.bold))
                .tracking(-0.5)
            Text(
                source == .meal
                    ? "Nutrition comes from your log. You choose what to say."
                    : source == .workout
                        ? "Your session is ready. Decide what others can see."
                        : "The details come from your calendar. Add the context."
            )
            .font(.subheadline)
            .foregroundStyle(timeOfDay.canvasSecondaryText)
        }
    }

    // MARK: - Already chosen

    /// What is being shared, when the caller named it. Drawn instead of the
    /// picker rather than as a preselected row inside it: the thing may sit
    /// outside the days the stores hold, and a list that cannot show the chosen
    /// item with a tick beside it reads as nothing being chosen at all.
    private func subjectSection(
        _ subject: String,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            EditorialSectionTitle(title: "Sharing")

            EditorialRuleGroup {
                EditorialRuleRow(showsDivider: false) {
                    Text(subject)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(timeOfDay.canvasPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(timeOfDay.accent)
                }
            }
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
                title: lockedSource.map { "Choose a \($0.itemNoun)" }
                    ?? "Choose something",
                detail: "A post is built from what you have already recorded."
            )

            if usesDayPicker {
                daySelector(timeOfDay: timeOfDay)
            }

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

    /// Opens on the newest day with something on it.
    ///
    /// Runs once, and only after the candidates have arrived — the workout
    /// list is fetched, so on first appearance it is empty and choosing then
    /// would always land on today.
    private func chooseOpeningDayIfNeeded() {
        guard usesDayPicker, !didChooseOpeningDay else { return }
        let days = allCandidates.compactMap(\.day)
        guard let newest = days.max() else { return }
        didChooseOpeningDay = true
        selectedDay = newest
    }

    private func emptyRow(timeOfDay: HomeTimeOfDay) -> some View {
        Text(dayIsEmptyMessage ?? source.emptyMessage)
            .font(.subheadline)
            .foregroundStyle(timeOfDay.canvasSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 22)
    }

    // MARK: - Photo

    /// The contract's ceiling, checked here so an oversized picture is refused
    /// with something readable rather than by a 400 after the upload.
    private static let photoByteLimit = 5 * 1024 * 1024

    private func photoSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            EditorialSectionTitle(
                title: "Photo",
                detail: "Optional. Shown above the card."
            )

            if let photoData, let image = UIImage(data: photoData) {
                VStack(alignment: .leading, spacing: 9) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .clipShape(
                            RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius)
                        )

                    Button("Remove photo") {
                        clearPhoto()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                }
            } else {
                PhotosPicker(
                    selection: $pickedPhoto,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(timeOfDay.accent)
                            .frame(width: 24)

                        Text("Add a photo")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(timeOfDay.canvasPrimaryText)

                        Spacer()

                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                    }
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
                }
            }

            if let photoError {
                Text(photoError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: pickedPhoto) { _, item in
            Task { await load(item) }
        }
    }

    /// Reads the chosen picture and works out what to call it.
    ///
    /// The picker hands over whatever the library holds, which on an iPhone is
    /// often HEIC. The contract accepts that, so the bytes are sent as they
    /// are rather than re-encoded; only a type the contract does not list is
    /// converted, and anything that cannot be identified at all is refused
    /// here rather than by the server.
    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        photoError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoError = "That photo could not be read."
                return
            }
            guard let contentType = Self.contentType(of: data) else {
                photoError = "That is not an image Repbase can post."
                return
            }
            guard data.count <= Self.photoByteLimit else {
                photoError = "That photo is larger than 5 MB."
                return
            }
            photoData = data
            photoContentType = contentType
        } catch {
            photoError = error.localizedDescription
        }
    }

    private func clearPhoto() {
        pickedPhoto = nil
        photoData = nil
        photoContentType = nil
        photoError = nil
    }

    /// The image type, read from the bytes themselves.
    ///
    /// `PhotosPickerItem.supportedContentTypes` is often empty for a library
    /// asset, and the file extension is not available at all, so the magic
    /// number is the only thing that actually says what this is.
    private static func contentType(of data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 12 else { return nil }
        if bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "image/jpeg"
        }
        if bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            return "image/png"
        }
        // RIFF....WEBP
        if bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return "image/webp"
        }
        // ....ftypheic / heix / hevc / mif1, the HEIF family the API accepts.
        if bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
            return "image/heic"
        }
        return nil
    }

    // MARK: - Caption

    private func captionSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            EditorialSectionTitle(title: "Caption", detail: "Optional.")

            TextField(
                "Say something about it",
                text: $caption,
                axis: .vertical
            )
            .lineLimit(2...6)
            .font(.body)
            .foregroundStyle(timeOfDay.canvasPrimaryText)
            .textInputAutocapitalization(.sentences)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Divider()
            }
            .onChange(of: caption) { _, value in
                if value.count > Self.captionLimit {
                    caption = String(value.prefix(Self.captionLimit))
                }
            }

            Text("\(caption.count)/\(Self.captionLimit)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Visibility

    /// Whether the load goes out with the workout.
    ///
    /// Separate from who can see the post, because it is a different question:
    /// this one is about how much of what you did is shown, not about who is
    /// shown it. Turning it off withholds the weights and the volume; the
    /// exercises, sets and reps still go — "4 × 8" is what was done, and it is
    /// the load people are shy about, not the count.
    private func weightsSection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            EditorialSectionTitle(title: "What to show")

            EditorialRuleGroup {
                Toggle(isOn: $showsWeights) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show the weights I lifted")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(timeOfDay.primaryText)
                        Text(
                            showsWeights
                                ? "Your top set and total volume go out with the workout."
                                : "Exercises, sets and reps still go out. The load does not."
                        )
                        .font(.caption)
                        .foregroundStyle(timeOfDay.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(timeOfDay.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private func visibilitySection(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            EditorialSectionTitle(title: "Who can see it")

            VStack(spacing: 0) {
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
            HStack(spacing: 12) {
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
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Divider()
                }
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

    /// Names what the sheet is for. A page that already knows the kind should
    /// say so at the top rather than leave the user to infer it from the list.
    private var composerTitle: String {
        if fixedSubject != nil { return "Share" }
        guard let lockedSource else { return "New Post" }
        return "Share a \(lockedSource.itemNoun.capitalized)"
    }

    /// The chosen picture as the API wants it, or nil when there is none.
    ///
    /// Encoded at the moment of posting rather than at the moment of picking:
    /// base64 is a third larger than the bytes, and a photo that is chosen and
    /// then removed should never have been expanded at all.
    private var attachedPhoto: PostPhoto? {
        guard let photoData, let photoContentType else { return nil }
        return PostPhoto(
            contentType: photoContentType,
            base64: photoData.base64EncodedString()
        )
    }

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
                visibility: visibility,
                showsWeights: showsWeights,
                photo: attachedPhoto
            )
            // Left open when it failed, so the error is read beside the post it
            // belongs to and the caption is not lost.
            if sent { dismiss() }
        }
    }

    // MARK: - What there is to post

    /// Everything postable of this kind, before the day filter.
    private var allCandidates: [PostCandidate] {
        switch source {
        case .workout: workoutCandidates
        case .meal: mealCandidates
        case .planner: plannerCandidates
        }
    }

    /// What the list shows: one day at a time for workouts and meals.
    ///
    /// The whole history was offered at once before, which for anyone who
    /// trains regularly is a scrolling wall of the same few names. The planner
    /// keeps the full list — its entries are already one per thing rather than
    /// one per attempt.
    private var candidates: [PostCandidate] {
        guard usesDayPicker else { return allCandidates }
        return allCandidates.filter { candidate in
            guard let day = candidate.day else { return false }
            return Calendar.current.isDate(day, inSameDayAs: selectedDay)
        }
    }

    private var usesDayPicker: Bool { source != .planner }

    /// Distinguishes "nothing on this day" from "nothing at all", which the
    /// source's own message cannot: with a day picker on screen, "you have no
    /// finished workouts" is wrong for someone who simply picked Tuesday.
    private var dayIsEmptyMessage: String? {
        guard usesDayPicker, !allCandidates.isEmpty else { return nil }
        let day = selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return "Nothing recorded on \(day). Pick another day above."
    }

    /// The seven days of the week `selectedDay` falls in, in the user's own
    /// first-weekday order.
    private var weekDays: [Date] {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDay) else {
            return []
        }
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: week.start)
        }
    }

    private func hasSomething(on day: Date) -> Bool {
        allCandidates.contains {
            guard let candidateDay = $0.day else { return false }
            return Calendar.current.isDate(candidateDay, inSameDayAs: day)
        }
    }

    private func changeWeek(by weeks: Int) {
        guard let moved = Calendar.current.date(
            byAdding: .weekOfYear,
            value: weeks,
            to: selectedDay
        ) else { return }
        selectedDay = moved
        // A day that is no longer on screen must not stay chosen underneath.
        selection = nil
    }

    /// A week of days, with a dot under the ones that have anything to post.
    private func daySelector(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    changeWeek(by: -1)
                } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 34)
                }
                .accessibilityLabel("Previous week")

                Spacer()

                Text(selectedDay.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    changeWeek(by: 1)
                } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 34)
                }
                .accessibilityLabel("Next week")
            }

            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                    Button {
                        selectedDay = day
                        selection = nil
                    } label: {
                        VStack(spacing: 5) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(timeOfDay.secondaryText)
                            Text(day.formatted(.dateTime.day()))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(
                                    isSelected ? RepbasePalette.cream : timeOfDay.primaryText
                                )
                                .frame(width: 30, height: 28)
                                .background(
                                    isSelected ? timeOfDay.accent : Color.clear,
                                    in: Capsule()
                                )
                            // Says where there is anything worth opening, so
                            // the empty days are not tapped one by one.
                            Circle()
                                .fill(timeOfDay.accent)
                                .frame(width: 5, height: 5)
                                .opacity(hasSomething(on: day) && !isSelected ? 1 : 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(hasSomething(on: day) ? "Has entries" : "Nothing recorded")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
        .padding(12)
        .repbaseCard(contentPadding: 2, cornerRadius: RepbaseDesign.cardRadius)
    }

    /// `YYYY-MM-DD` back into a date, in the device's own calendar.
    private static func day(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }

    private var workoutCandidates: [PostCandidate] {
        workoutStore.postableSessions
            // Sessions that recorded nothing are not posts. Starting a day and
            // stopping leaves a finished session behind, which is why the same
            // workout appeared six times over: every abandoned start was
            // offered as something to share.
            .filter(\.recordedSomething)
            .map { session in
                PostCandidate(
                    kind: .workout,
                    sourceID: session.sessionID,
                    title: session.workoutName,
                    subtitle: Self.sessionSubtitle(session),
                    day: session.performedAt
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
                        subtitle: "\(PostDateText.label(forKey: day.key)) · \(calories) kcal",
                        day: Self.day(fromKey: day.key)
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
