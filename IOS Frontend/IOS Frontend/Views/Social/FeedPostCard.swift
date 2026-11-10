//
//  FeedPostCard.swift
//  IOS Frontend
//
//  A post in the media-first feed: watch it, then try it.
//

import AVFoundation
import SwiftUI

/// The feed's player, drawn without controls. `VideoPlayer` brings a
/// scrubber and a transport bar, which belong on a screen for watching one
/// clip and not on a card in a list of them.
private struct FeedPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer } // swiftlint:disable:this force_cast
    }

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: Surface, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    static func dismantleUIView(_ view: Surface, coordinator: ()) {
        view.playerLayer.player = nil
    }
}

/// One post, in the four shapes the approved design gives it:
///
/// - a gym moment: the clip or photo, and the words over it;
/// - a workout or a recipe: the same, with what was done underneath and one
///   clear button to keep it;
/// - a take: any of those, saying whose post it answers.
///
/// The media is the card. What can be tried sits under it as its own row, so
/// saving is one tap from the feed and never needs the details opened first;
/// tapping the row's text opens them.
struct FeedPostCard: View {
    let post: FeedPost
    let timeOfDay: HomeTimeOfDay
    var openComments: () -> Void
    var openAuthor: (Int) -> Void
    var openPost: () -> Void
    /// Raises the workout or recipe sheet.
    var openAttachment: () -> Void
    /// Raises the takes of this post.
    var openTakes: () -> Void

    @Environment(SocialStore.self) private var store
    @Environment(FeedPlaybackCoordinator.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reportingPost: FeedPost?

    private var shown: RepostedPost { post.displayed }
    private var clip: PostVideoMedia? {
        guard post.isPublished, let video = shown.video, video.canPlay else { return nil }
        return video
    }
    private var posterURL: URL? { clip?.thumbnailURL ?? shown.feedImageURL ?? shown.imageURL }
    private var isActive: Bool { playback.activePostID == shown.id }
    private var hasMedia: Bool { clip != nil || posterURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if post.repostOf != nil {
                Label("\(post.author.displayName) reposted", systemImage: "arrow.2.squarepath")
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .lineLimit(1)
            }
            if let message = post.publicationMessage {
                Label(message, systemImage: post.moderationStatus == "rejected" ? "exclamationmark.shield" : "clock")
                    .font(.community(.footnote))
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            media
            if shown.workout != nil || shown.meal != nil {
                attachmentRow
            }
            if post.takeCount > 0 || post.viewerCanTake {
                takesRow
            }
        }
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.vertical, 10)
        .sheet(item: $reportingPost) { target in
            PostReportSheet(post: target, timeOfDay: timeOfDay)
        }
    }

    // MARK: The media, and the words over it

    private var media: some View {
        ZStack {
            backdrop
            // Dark at both ends so white text holds on any picture, and
            // clear through the middle where the picture is the point.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.72), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)
            VStack(spacing: 0) {
                topRow
                Spacer(minLength: 12)
                HStack(alignment: .bottom, spacing: 12) {
                    words
                    Spacer(minLength: 0)
                    actions
                }
            }
            .padding(14)
        }
        // Tall when there is something to look at, and only as tall as its
        // words when there is not.
        .aspectRatio(hasMedia ? 3.0 / 4.0 : nil, contentMode: .fit)
        .frame(maxWidth: .infinity, minHeight: hasMedia ? nil : 220)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            if clip != nil { playback.toggle(postID: shown.id) } else { openPost() }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let posterURL {
            // The poster stays under the player, so a clip that is still
            // buffering shows its first frame rather than a black box.
            Color.black.overlay {
                RemoteImage(url: posterURL, maxPixel: 1100) {
                    Color.black
                } failure: {
                    Color.black
                }
                .scaledToFill()
            }
            .overlay {
                if isActive, clip != nil {
                    FeedPlayerSurface(player: playback.player)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .clipped()
            .accessibilityHidden(true)
        } else if isActive, clip != nil {
            Color.black.overlay { FeedPlayerSurface(player: playback.player) }.clipped()
        } else {
            // A workout or recipe posted with no picture: the card's own
            // colour, so it reads as a card and not as a missing image.
            LinearGradient(
                colors: [RepbasePalette.espresso, RepbasePalette.charcoal],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: 8) {
            if let kindLabel {
                Text(kindLabel)
                    .font(.community(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if let clip {
                    Text(Duration.milliseconds(clip.durationMilliseconds),
                         format: .time(pattern: .minuteSecond))
                        .font(.community(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.45), in: Capsule())
                        .accessibilityLabel("Video")
                    if isActive {
                        Button {
                            playback.isMuted.toggle()
                        } label: {
                            Image(systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(playback.isMuted ? "Unmute" : "Mute")
                    } else if playback.failedPostIDs.contains(shown.id) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("This video could not play. Please try again.")
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.45), in: Circle())
                            .accessibilityLabel("Play video")
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
    }

    private var kindLabel: LocalizedStringKey? {
        if post.isTake { return "Your take" }
        if shown.workout != nil { return "Workout" }
        if shown.meal != nil { return "Recipe" }
        return nil
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 1) {
                    Text(shown.author.displayName)
                        .font(.community(.subheadline, weight: .bold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(verbatim: "@\(shown.author.username)").lineLimit(1)
                        Text(verbatim: "·")
                        Text(shown.displayDate, format: .relative(presentation: .numeric)).lineLimit(1)
                    }
                    .font(.community(.caption))
                    .opacity(0.85)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { openAuthor(shown.author.id) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens this person's profile")

            if !shown.caption.isEmpty {
                Text(shown.caption)
                    .font(.community(.subheadline, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let recommendation = post.recommendation, !post.viewerIsAuthor {
                Text(recommendation.label)
                    .font(.community(.caption))
                    .opacity(0.85)
                    .lineLimit(1)
            }
            if let sound = post.sound {
                Label {
                    // The sound's own name and its owner's: nothing to
                    // translate, and nothing to build a sentence from.
                    Text(verbatim: "\(sound.title) · \(sound.ownerName)")
                } icon: {
                    Image(systemName: "music.note")
                }
                .font(.community(.caption))
                .lineLimit(1)
                .opacity(0.9)
            }
            if let source = post.source {
                Label {
                    if let name = source.authorName {
                        Text("Your take on \(name)")
                    } else {
                        Text("Original no longer available")
                    }
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .font(.community(.caption, weight: .semibold))
                .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    @ViewBuilder
    private var avatar: some View {
        let initials = Text(shown.author.initials)
            .font(.community(.footnote, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(RepbasePalette.caramel.opacity(0.85), in: Circle())
        if let photo = shown.author.photoURL, let url = URL(string: photo) {
            RemoteImage(url: url, maxPixel: 132) { initials } failure: { initials }
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        } else {
            initials
        }
    }

    private var actions: some View {
        VStack(spacing: 6) {
            if post.isPublished {
                action(
                    symbol: post.viewerHasLiked ? "heart.fill" : "heart",
                    count: post.likeCount,
                    tint: post.viewerHasLiked ? Color(hex: 0xE0446B) : .white,
                    label: post.viewerHasLiked
                        ? String(localized: "Unlike", bundle: .app, locale: .app)
                        : String(localized: "Like", bundle: .app, locale: .app, comment: "Button that likes a post")
                ) { Task { await store.toggleLike(post) } }
                .disabled(store.isLikePending(post))
                action(
                    symbol: "bubble.left", count: post.commentCount, tint: .white,
                    label: String(localized: "Comments", bundle: .app, locale: .app),
                    perform: openComments
                )
            }
            if post.viewerIsAuthor || post.offersModeration {
                PostOptionsMenu(post: post, report: { reportingPost = post }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    private func action(
        symbol: String, count: Int, tint: Color, label: String, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                if count > 0 {
                    Text(count, format: .number.notation(.compactName))
                        .font(.community(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(count > 0 ? Text(count, format: .number) : Text(verbatim: ""))
    }

    /// Who else made this, and the way in to making it yours.
    private var takesRow: some View {
        Button(action: openTakes) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                if post.takeCount > 0 {
                    Text("\(post.takeCount) takes")
                } else {
                    Text("Post your take")
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .font(.community(.footnote, weight: .semibold))
            .foregroundStyle(timeOfDay.canvasSecondaryText)
            .padding(.horizontal, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: What can be tried

    private var attachmentRow: some View {
        HStack(spacing: 12) {
            Button(action: openAttachment) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(shown.workout != nil ? "Workout" : "Recipe")
                        .font(.community(size: 11, weight: .bold))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(timeOfDay.accent)
                    Text(shown.workout?.title ?? shown.meal?.name ?? "")
                        .font(.community(.subheadline, weight: .semibold))
                        .foregroundStyle(timeOfDay.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    summary
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(shown.workout != nil ? "Opens the workout" : "Opens the recipe")

            SaveAttachmentButton(post: post, timeOfDay: timeOfDay, isWide: false)
        }
        .padding(14)
        .background(timeOfDay.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(timeOfDay.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let workout = shown.workout {
            HStack(spacing: 4) {
                Text("\(workout.exerciseCount) exercises")
                Text(verbatim: "·")
                Text("\(workout.totalSetCount) sets")
            }
        } else if let meal = shown.meal {
            Text("\(NSDecimalNumber(decimal: meal.totalCalories).intValue) kcal")
        }
    }
}

/// Keeps a post's workout or recipe. On the card and in the sheet, the same
/// button with the same three states, so what one says the other says.
struct SaveAttachmentButton: View {
    let post: FeedPost
    let timeOfDay: HomeTimeOfDay
    /// Full width in the sheet; hugging its label on a card.
    let isWide: Bool

    @Environment(SocialStore.self) private var store

    private var isWorkout: Bool { post.displayed.workout != nil }
    private var isSaving: Bool {
        isWorkout ? store.isSavingWorkout(from: post.id) : store.isSavingMeal(from: post.id)
    }
    private var canSave: Bool { isWorkout ? post.offersWorkoutToSave : post.offersMealToSave }

    var body: some View {
        if canSave || post.viewerHasSaved {
            Button {
                Task {
                    if isWorkout { await store.saveWorkout(from: post) } else { await store.saveMeal(from: post) }
                }
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView().tint(timeOfDay.onPrimaryAction)
                    } else {
                        Image(systemName: post.viewerHasSaved ? "checkmark" : "bookmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(post.viewerHasSaved ? "Saved" : isWorkout ? "Save workout" : "Save recipe")
                        .font(.community(.footnote, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(post.viewerHasSaved ? timeOfDay.primaryText : timeOfDay.onPrimaryAction)
                .padding(.horizontal, 16)
                .frame(maxWidth: isWide ? .infinity : nil, minHeight: 44)
                .background(
                    post.viewerHasSaved ? timeOfDay.surfaceRaised : timeOfDay.primaryActionSurface,
                    in: Capsule()
                )
                .overlay {
                    if post.viewerHasSaved {
                        Capsule().strokeBorder(timeOfDay.border, lineWidth: 1)
                    }
                }
            }
            .buttonStyle(.plain)
            // Saved is a state, not an action: saving twice makes nothing.
            .disabled(isSaving || post.viewerHasSaved)
        }
    }
}
