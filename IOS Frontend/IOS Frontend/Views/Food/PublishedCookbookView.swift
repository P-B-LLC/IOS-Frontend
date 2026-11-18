import SwiftUI

struct PublishedCookbookView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workoutVisualPhase) private var phase
    let post: FeedPost
    @State private var cookbook: PublishedCookbook?
    @State private var loading = false
    @State private var saving = false
    @State private var saved = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if loading { ProgressView("Loading…") }
                if let error {
                    Text(error).font(.community(.footnote)).foregroundStyle(.red)
                    Button("Retry") { Task { await load() } }
                }
                if let cookbook {
                    RepbaseScreenHeader(eyebrow: "COOKBOOK", title: LocalizedStringKey(cookbook.name),
                                        detail: "\(cookbook.recipes.count) recipes · Ingredients & steps included")
                    ForEach(cookbook.recipes) { recipe in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(recipe.ingredients) { ingredient in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(ingredient.name)
                                        Spacer()
                                        Text("\(ingredient.servings.nutritionText) servings")
                                    }.font(.community(.subheadline))
                                }
                                if !recipe.cookingInstructions.isEmpty {
                                    Text("How it's made").font(.community(.headline))
                                    Text(recipe.cookingInstructions).font(.community(.body))
                                }
                            }.padding(.top, 12)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(recipe.name).font(.community(.headline))
                                Text("\(recipe.totalNutrition.calories.nutritionText) kcal · \(recipe.totalNutrition.proteinGrams.nutritionText) g protein")
                                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                            }
                        }
                        .padding(16)
                        .background(phase.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                    }
                    if !post.viewerIsAuthor {
                        Button {
                            guard !saving else { return }
                            saving = true
                            Task {
                                defer { saving = false }
                                if await social.saveCookbook(from: post) { saved = true; error = nil }
                                else { error = social.errorMessage }
                            }
                        } label: {
                            if saved || post.viewerHasSaved { Label("Saved", systemImage: "checkmark") }
                            else { Label("Save cookbook", systemImage: "books.vertical") }
                        }
                        .buttonStyle(RepbasePrimaryButtonStyle())
                        .disabled(saved || post.viewerHasSaved || saving)
                    }
                    Text("Saves a private cookbook with all its recipes. You can make it your own.")
                        .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                }
            }.padding(RepbaseDesign.pageInset)
        }
        .navigationTitle("Cookbook").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .repbaseScreen(phase)
        .saveFeedback(isSaving: saving, error: nil)
        .task(id: post.id) { await load() }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        cookbook = await social.loadCookbook(postID: post.id)
        if cookbook == nil { error = social.errorMessage ?? String(localized: "Couldn't load this cookbook. Please try again.", bundle: .app, locale: .app) }
    }
}
