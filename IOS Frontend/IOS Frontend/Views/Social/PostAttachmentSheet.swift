//
//  PostAttachmentSheet.swift
//  IOS Frontend
//
//  A post's workout or recipe, opened from its card.
//

import SwiftUI

/// What a post's author did, in full: every exercise of the workout, or the
/// recipe's ingredients and method, with the button to keep it.
///
/// A feed page carries only the title and totals. The rows are read here,
/// for this one post, when somebody asks -- so scrolling past a hundred
/// recipes costs a hundred summaries and not a hundred ingredient lists.
struct PostAttachmentSheet: View {
    let postID: Int
    let timeOfDay: HomeTimeOfDay

    @Environment(SocialStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var post: FeedPost? { store.post(withID: postID) }

    var body: some View {
        ScrollView {
            if let post {
                VStack(alignment: .leading, spacing: 18) {
                    header(post)
                    let detailed = store.detailed(post)?.displayed
                    if let workout = detailed?.workout {
                        exercises(workout)
                    } else if let meal = detailed?.meal {
                        recipe(meal)
                    } else if store.failedDetailsFor.contains(post.displayed.id) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Could not load this post.")
                                .font(.community(.subheadline))
                                .foregroundStyle(timeOfDay.secondaryText)
                            Button("Try again") { Task { await store.loadDetails(for: post) } }
                                .font(.community(.subheadline, weight: .semibold))
                                .frame(minHeight: 44)
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                    SaveAttachmentButton(post: post, timeOfDay: timeOfDay, isWide: true)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 28)
            }
        }
        .background(timeOfDay.surface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: postID) {
            if let post { await store.loadDetails(for: post) }
        }
    }

    private func header(_ post: FeedPost) -> some View {
        let shown = post.displayed
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(shown.workout != nil ? "The workout" : "The recipe")
                    .font(.community(.subheadline, weight: .semibold))
                    .foregroundStyle(timeOfDay.secondaryText)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
            }
            Text(shown.workout?.title ?? shown.meal?.name ?? "")
                .font(.community(.title2, weight: .bold))
                .foregroundStyle(timeOfDay.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("By \(shown.author.displayName)")
                .font(.community(.footnote, weight: .semibold))
                .foregroundStyle(timeOfDay.accent)
        }
    }

    private func exercises(_ workout: PostWorkoutSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(workout.exerciseCount) exercises")
                .font(.community(.footnote, weight: .bold))
                .foregroundStyle(timeOfDay.accent)
                .padding(.bottom, 6)
            ForEach(workout.exercises) { line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(line.name)
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text("\(line.setCount) sets")
                        .font(.community(.footnote))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                Divider().overlay(timeOfDay.border)
            }
        }
    }

    private func recipe(_ meal: PostMealSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ingredients")
                    .font(.community(.subheadline, weight: .bold))
                    .foregroundStyle(timeOfDay.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(meal.entries.map(\.name).formatted(.list(type: .and).locale(.app)))
                    .font(.community(.subheadline))
                    .foregroundStyle(timeOfDay.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !meal.cookingInstructions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Make it")
                        .font(.community(.subheadline, weight: .bold))
                        .foregroundStyle(timeOfDay.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text(meal.cookingInstructions)
                        .font(.community(.subheadline))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
