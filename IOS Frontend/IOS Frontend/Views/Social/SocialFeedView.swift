//
//  SocialFeedView.swift
//  IOS Frontend
//
//  What the people you follow have posted.
//

import SwiftUI

struct SocialFeedView: View {
    @Environment(SocialStore.self) private var store
    @State private var isComposing = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            screen(timeOfDay: HomeTimeOfDay(date: context.date))
        }
    }

    private func screen(timeOfDay: HomeTimeOfDay) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                header(timeOfDay: timeOfDay)

                if let message = store.errorMessage {
                    notice(message, symbol: "exclamationmark.triangle.fill", timeOfDay: timeOfDay)
                }

                if store.isLoading && store.feed.isEmpty {
                    ProgressView().padding(.top, 40)
                } else if store.feed.isEmpty {
                    emptyState(timeOfDay: timeOfDay)
                } else {
                    ForEach(store.feed) { post in
                        PostCard(post: post, timeOfDay: timeOfDay)
                            .task {
                                // The last card asks for the next page as it
                                // comes into view, so the feed keeps going
                                // without a button to press.
                                if post.id == store.feed.last?.id {
                                    await store.loadMore()
                                }
                            }
                    }

                    if store.isLoadingMore {
                        ProgressView().padding(.vertical, 12)
                    }
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 16)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .toolbar(.hidden, for: .navigationBar)
        .homeTimeScreen(timeOfDay)
        .sheet(isPresented: $isComposing) {
            PostComposerView()
        }
    }

    private func header(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RepbaseScreenHeader(
                eyebrow: "Community",
                title: "Social",
                detail: "Training updates and progress from the people you follow."
            )

            composeButton(timeOfDay: timeOfDay)
        }
        .padding(.bottom, 2)
    }

    /// Opens the composer. Kept beside the title rather than floating over the
    /// feed: the bottom bar already sits there, and a second round button above
    /// it read as part of the same control.
    private func composeButton(timeOfDay: HomeTimeOfDay) -> some View {
        Button {
            isComposing = true
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)
                .frame(width: 44, height: 44)
                .background(timeOfDay.accent.opacity(0.11), in: Circle())
                .overlay {
                    Circle().strokeBorder(timeOfDay.canvasBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New post")
    }

    private func emptyState(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)
            Text("Nothing here yet")
                .font(.headline)
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text("Posts from people you follow show up here. Share a workout, a meal, or something off your calendar to start your own.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Repeats the header's button where the eye already is. An empty
            // feed is exactly when the one in the corner goes unnoticed.
            Button("Write a post") { isComposing = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(timeOfDay.accent)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 22)
    }

    private func notice(
        _ message: String,
        symbol: String,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(timeOfDay.accent)
            Text(message)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(timeOfDay.canvasSecondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(timeOfDay.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// One post. The body is chosen by which snapshot came back rather than by
/// `kind`, so a post whose kind this build does not know still draws whatever
/// of it is recognisable.
struct PostCard: View {
    let post: FeedPost
    let timeOfDay: HomeTimeOfDay

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            author

            if let imageURL = post.imageURL {
                photo(imageURL)
            }

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.subheadline)
                    .foregroundStyle(timeOfDay.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let workout = post.workout {
                workoutBody(workout)
            } else if let meal = post.meal {
                mealBody(meal)
            } else if let planner = post.planner {
                plannerBody(planner)
            } else {
                unsupportedBody
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .repbaseDepthSurface(cornerRadius: RepbaseDesign.featureRadius)
    }

    /// The author's photo, above the numbers it was posted with.
    ///
    /// A failure draws nothing rather than a broken-image placeholder: the
    /// card's real content is the snapshot underneath, and it should still
    /// read cleanly when the picture cannot be fetched.
    private func photo(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            default:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: RepbaseDesign.cardRadius))
    }

    private var author: some View {
        HStack(spacing: 10) {
            Text(post.author.initials)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(timeOfDay.accent, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(post.author.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(timeOfDay.primaryText)
                Text("@\(post.author.username)")
                    .font(.caption2)
                    .foregroundStyle(timeOfDay.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(post.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(timeOfDay.secondaryText)
                if post.visibility != .publicToAll {
                    Image(systemName: post.visibility.symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
            }
        }
    }

    // MARK: - Bodies

    private func workoutBody(_ workout: PostWorkoutSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            kindLabel("Workout", symbol: "dumbbell.fill")

            Text(workout.title)
                .font(.headline)
                .foregroundStyle(timeOfDay.primaryText)

            HStack(spacing: 16) {
                statistic("\(workout.exerciseCount)", "exercises")
                statistic("\(workout.totalSetCount)", "sets")
                if let volume = workout.totalVolumeKg {
                    statistic(volume.nutritionText, "kg lifted")
                }
                if let distance = workout.routeDistanceKm {
                    statistic(
                        String(
                            format: "%.2f",
                            ImperialUnits.miles(fromKilometers: distance.nutritionDouble)
                        ),
                        "mi"
                    )
                }
            }

            if !workout.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(workout.exercises.prefix(4)) { line in
                        HStack(spacing: 6) {
                            Text(line.name)
                                .font(.caption)
                                .foregroundStyle(timeOfDay.primaryText)
                            Spacer(minLength: 6)
                            Text(Self.setSummary(line))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(timeOfDay.secondaryText)
                        }
                    }
                    if workout.exercises.count > 4 {
                        Text("+\(workout.exercises.count - 4) more")
                            .font(.caption2)
                            .foregroundStyle(timeOfDay.secondaryText)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func mealBody(_ meal: PostMealSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            kindLabel("Meal", symbol: "fork.knife")

            Text(meal.name)
                .font(.headline)
                .foregroundStyle(timeOfDay.primaryText)

            HStack(spacing: 16) {
                statistic(meal.totalCalories.nutritionText, "kcal")
                statistic("\(meal.totalProteinGrams.nutritionText)g", "protein")
                statistic("\(meal.totalCarbohydrateGrams.nutritionText)g", "carbs")
                statistic("\(meal.totalFatGrams.nutritionText)g", "fat")
            }

            if !meal.entries.isEmpty {
                Text(meal.entries.map(\.name).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(timeOfDay.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func plannerBody(_ planner: PostPlannerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            kindLabel(planner.kind == "event" ? "Event" : "Task", symbol: "checklist")

            Text(planner.title)
                .font(.headline)
                .foregroundStyle(timeOfDay.primaryText)

            HStack(spacing: 8) {
                Text(planner.scheduledDate)
                if let time = planner.scheduledTime {
                    Text(time.hasSuffix(":00") ? String(time.dropLast(3)) : time)
                }
                if planner.isComplete {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption)
            .foregroundStyle(timeOfDay.secondaryText)
        }
    }

    /// A post of a kind this build has never heard of. Drawn as a placeholder
    /// rather than skipped, so the feed does not silently go short.
    private var unsupportedBody: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
            Text("This post needs a newer version of Repbase.")
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(timeOfDay.secondaryText)
    }

    // MARK: - Pieces

    private func kindLabel(_ title: String, symbol: String) -> some View {
        Label(title.uppercased(), systemImage: symbol)
            .font(.system(size: 9, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(timeOfDay.accent)
    }

    private func statistic(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(timeOfDay.primaryText)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(timeOfDay.secondaryText)
        }
    }

    private static func setSummary(_ line: PostExerciseLine) -> String {
        guard let weight = line.topSetWeightKg, let reps = line.topSetReps else {
            return "\(line.setCount) sets"
        }
        return "\(line.setCount) × \(reps) @ \(weight.nutritionText) kg"
    }
}
