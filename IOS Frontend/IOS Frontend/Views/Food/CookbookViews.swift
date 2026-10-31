import SwiftUI

struct CookbookRow: View {
    @Environment(\.workoutVisualPhase) private var phase
    let cookbook: Cookbook

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.community(.title2))
                .foregroundStyle(phase.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(cookbook.name).font(.community(.headline))
                    .foregroundStyle(phase.primaryText)
                Text("\(cookbook.recipeCount) / \(cookbook.capacity) recipes")
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                if cookbook.isFull {
                    Text("Full").font(.community(.caption, weight: .semibold))
                        .foregroundStyle(phase.secondaryText)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.community(.caption, weight: .bold))
                .foregroundStyle(phase.accent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(phase.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

struct CookbookLibraryView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.workoutVisualPhase) private var phase
    @Environment(\.scenePhase) private var scenePhase
    let referenceDate: Date
    var destination: SavedMealsView.Destination?
    @State private var editing: Cookbook?
    @State private var deleting: Cookbook?
    @State private var creating = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                RepbaseScreenHeader(eyebrow: "YOUR RECIPE LIBRARY", title: "Your cookbooks",
                                    detail: "Good food, kept together. Find the recipe that fits your day.")
                if store.isLoadingCookbooks && store.cookbooks.isEmpty { ProgressView("Loading…") }
                if let error = store.cookbookError {
                    Text(error).font(.community(.footnote)).foregroundStyle(.red)
                    Button("Retry") { Task { await store.reloadCookbookLibrary() } }
                } else if store.cookbooks.isEmpty && !store.isLoadingCookbooks {
                    Text("Create your first cookbook, then save recipes into it.")
                        .font(.community(.body)).foregroundStyle(phase.secondaryText)
                }
                ForEach(store.cookbooks) { book in
                    NavigationLink {
                        SavedMealsView(referenceDate: referenceDate, destination: destination, cookbookID: book.id)
                    } label: { CookbookRow(cookbook: book) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename cookbook", systemImage: "pencil") { editing = book }
                        Button("Delete cookbook", systemImage: "trash", role: .destructive) { deleting = book }
                            .disabled(book.recipeCount > 0)
                    }
                    .accessibilityAction(named: Text("Rename cookbook")) { editing = book }
                }
                Button("New cookbook", systemImage: "plus") { creating = true }
                    .buttonStyle(RepbasePrimaryButtonStyle())
                Text("Only you can see your cookbooks until you choose to post one.")
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
            }
            .padding(.horizontal, RepbaseDesign.pageInset).padding(.vertical, 18)
        }
        .sheet(isPresented: $creating) { NavigationStack { CookbookEditorView() } }
        .sheet(item: $editing) { book in NavigationStack { CookbookEditorView(existing: book) } }
        .confirmationDialog("Delete cookbook?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            if let book = deleting {
                Button("Delete cookbook", role: .destructive) { Task { _ = await store.deleteCookbook(book) } }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.reloadCookbookLibrary() } }
        }
    }
}

struct CookbookEditorView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workoutVisualPhase) private var phase
    let existing: Cookbook?
    @State private var name: String
    @State private var saving = false
    @State private var error: String?
    @State private var requestKey = UUID()

    init(existing: Cookbook? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
    }

    var body: some View {
        Form {
            Section {
                Text("Make room for good food.").font(.community(.title2, weight: .bold))
                Text("A name is all you need. Start small and add recipes as you go.")
                    .font(.community(.body)).foregroundStyle(phase.secondaryText)
            }
            Section("Cookbook name") {
                TextField("For example: Weeknight favorites", text: $name)
                    .font(.community(.body)).textInputAutocapitalization(.sentences)
                    .onChange(of: name) { _, value in
                        if value.count > 80 { name = String(value.prefix(80)) }
                        requestKey = UUID()
                    }
            } footer: { Text("Up to 20 recipes. You can rename it anytime.") }
        }
        .navigationTitle(existing == nil ? String(localized: "New cookbook", bundle: .app, locale: .app) : String(localized: "Rename cookbook", bundle: .app, locale: .app))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }
        .saveFeedback(isSaving: saving, error: error)
        .repbaseScreen(phase)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        error = nil
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { saving = false }
            let success: Bool
            if let existing { success = await store.renameCookbook(existing, name: value) }
            else { success = await store.createCookbook(name: value, key: requestKey) != nil }
            if success { dismiss() }
            else { error = store.cookbookError ?? SaveFailure.alreadySaving }
        }
    }
}

struct CookbookPickerView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workoutVisualPhase) private var phase
    var excluding: Int? = nil
    let onChoose: (Cookbook) async -> Bool
    @State private var creating = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                RepbaseScreenHeader(eyebrow: "SAVE RECIPE", title: "Where should this live?",
                                    detail: "Choose a cookbook for this recipe.")
                if store.isLoadingCookbooks { ProgressView("Loading…") }
                if let message = error ?? store.cookbookError {
                    Text(message).foregroundStyle(.red).font(.community(.footnote))
                    Button("Retry") { Task { await store.reloadCookbookLibrary() } }
                }
                ForEach(store.cookbooks.filter { $0.id != excluding }) { book in
                    Button {
                        guard !saving else { return }
                        saving = true
                        error = nil
                        Task {
                            defer { saving = false }
                            if await onChoose(book) { dismiss() }
                            else { error = store.cookbookError ?? store.errorMessage ?? String(localized: "Couldn't save. Please try again.", bundle: .app, locale: .app) }
                        }
                    } label: { CookbookRow(cookbook: book) }
                    .buttonStyle(.plain).disabled(book.isFull || saving)
                    .opacity(book.isFull ? 0.55 : 1)
                }
                Button("New cookbook", systemImage: "plus") { creating = true }
                    .buttonStyle(RepbasePrimaryButtonStyle())
                Text("Full cookbooks stay visible. Choose another home or create one.")
                    .font(.community(.caption)).foregroundStyle(phase.secondaryText)
            }.padding(RepbaseDesign.pageInset)
        }
        .navigationTitle("Choose a cookbook").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .sheet(isPresented: $creating) { NavigationStack { CookbookEditorView() } }
        .task(id: store.isConnected) { if store.isConnected { await store.reloadCookbookLibrary() } }
        .refreshable { await store.reloadCookbookLibrary() }
        .saveFeedback(isSaving: saving, error: nil)
        .repbaseScreen(phase)
    }
}

struct CookbookSelectionField: View {
    @Environment(FoodTrackingStore.self) private var store
    @Binding var selection: Int?
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cookbook").font(.community(.headline))
            Button { choosing = true } label: {
                HStack {
                    Image(systemName: "books.vertical")
                    if let selected = store.cookbooks.first(where: { $0.id == selection }) { Text(selected.name) }
                    else { Text("Choose a cookbook") }
                    Spacer()
                    Image(systemName: "chevron.right")
                }.font(.community(.body)).padding(.vertical, 12)
            }.buttonStyle(.plain)
        }
        .sheet(isPresented: $choosing) {
            NavigationStack {
                CookbookPickerView { book in selection = book.id; return true }
            }
        }
    }
}

struct CookbookPostComposer: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workoutVisualPhase) private var phase
    let cookbook: Cookbook
    @State private var caption = ""
    @State private var visibility: PostVisibility = .followers
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                CookbookRow(cookbook: cookbook)
                Text("Ingredients, nutrition and cooking steps are shared as they are now. Later edits stay in your private cookbook.")
                    .font(.community(.footnote)).foregroundStyle(phase.secondaryText)
            }
            Section("Caption") {
                TextField("Say something about your cookbook", text: $caption, axis: .vertical)
                    .lineLimit(3...6)
                    .onChange(of: caption) { _, value in if value.count > 300 { caption = String(value.prefix(300)) } }
            }
            Section("Audience") {
                Picker("Who can see this?", selection: $visibility) {
                    ForEach(PostVisibility.allCases) { value in Text(value.title).tag(value) }
                }
            }
            Button("Post cookbook", systemImage: "square.and.arrow.up") {
                guard !saving else { return }
                saving = true
                Task {
                    defer { saving = false }
                    if await social.post(kind: .cookbook, sourceID: cookbook.id, caption: caption, visibility: visibility) { dismiss() }
                    else { error = social.errorMessage ?? String(localized: "Couldn't save. Please try again.", bundle: .app, locale: .app) }
                }
            }.disabled(cookbook.recipeCount == 0 || saving)
        }
        .navigationTitle("Post cookbook").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .saveFeedback(isSaving: saving, error: error).repbaseScreen(phase)
    }
}
