//
//  FoodPickerView.swift
//  IOS Frontend
//
//  Chooses how a food gets added to a meal: reuse something already logged,
//  search the catalogue, scan a barcode, or enter a label manually.
//

import Foundation
import RepbaseAPI
import SwiftUI

struct FoodPickerView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var pendingAdd: FoodEntry?
    @State private var draftSaved = false

    let date: Date
    let mealID: FoodMeal.ID

    @State private var searchText = ""
    @State private var submittedQuery = ""
    @State private var searchRevision = 0
    @State private var showingBarcode = false
    @State private var scannedBarcode: String?
    @State private var databaseResults: [FoodCatalogueCandidate] = []
    @State private var isSearchingDatabase = false
    @State private var databaseError: String?
    @State private var pendingCandidate: FoodCatalogueCandidate?
    @State private var detailRevision = 0
    @State private var loadingCandidateID: String?
    @State private var detailError: String?
    @State private var selectedFood: FoodEntry?
    @State private var servingDescription = String(localized: "1 serving of this food entry", bundle: .app, locale: .app)
    @State private var savedFood: FoodEntry?
    @State private var openedInitialFood = false
    @State private var showingSources = false
    var initialFood: FoodEntry? = nil
    #if DEBUG
    var previewScenario: String? = nil
    #endif

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let savedFood {
                    VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 54)).foregroundStyle(RepbaseDesign.success)
                    Text("Added to your meal")
                        .font(.community(.largeTitle, weight: .bold))
                    Text(savedFood.name).font(.community(.headline))
                    Text("\(savedFood.servings.nutritionText) servings · \(savedFood.totalNutrition.calories.nutritionText) kcal")
                        .foregroundStyle(.secondary)
                    Button("Add another food") {
                        self.savedFood = nil
                        pendingAdd = nil
                        draftSaved = false
                        searchText = ""
                    }.buttonStyle(RepbasePrimaryButtonStyle())
                    Button("Done") { dismiss() }.buttonStyle(RepbasePrimaryButtonStyle())
                    }
                    .padding(RepbaseDesign.pageInset)
                } else {
                    searchArea
                    VStack(alignment: .leading, spacing: 24) {
                        if let pendingAdd {
                            Button("Retry saving \(pendingAdd.name)") { add(pendingAdd) }
                                .font(.community(.subheadline, weight: .semibold))
                                .frame(minHeight: 44)
                                .disabled(isSaving)
                        }
                        if !submittedQuery.isEmpty { databaseEditorialSection }
                        if submittedQuery.isEmpty || !filteredRecents.isEmpty {
                            recentEditorialSection
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Add Food")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.disabled(isSaving)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingSources = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Food data & sources")
            }
        }
        .tint(RepbaseTactileDesign.accentText)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { showingSources = true } label: {
                HStack(spacing: 8) {
                    Label("Food data & sources", systemImage: "info.circle")
                    Image(systemName: "chevron.forward").accessibilityHidden(true)
                }
                .font(.community(.caption))
                .foregroundStyle(RytivoSunriseDesign.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(.systemBackground))
        }
        .saveFeedback(isSaving: isSaving, error: saveError)
        .modifier(FoodPickerDraftRecovery(enabled: !isPreview, mealID: mealID,
                                         pendingAdd: $pendingAdd, saved: $draftSaved, error: $saveError))
        .task(id: searchRevision) { await searchDatabase() }
        .task(id: detailRevision) { await loadProductDetails() }
        .onChange(of: searchText) { _, _ in
            #if DEBUG
            if previewScenario != nil { return }
            #endif
            // Typing invalidates an old response but never spends a provider call.
            cancelProductDetails()
            submittedQuery = ""
            databaseResults = []
            databaseError = nil
            isSearchingDatabase = false
        }
        .sheet(isPresented: $showingBarcode, onDismiss: {
            if let code = scannedBarcode {
                scannedBarcode = nil
                cancelProductDetails()
                submittedQuery = "barcode:" + code
                searchRevision += 1
            }
        }) {
            FoodBarcodeSheet { code in
                scannedBarcode = code
                showingBarcode = false
            }
        }
        .onAppear {
            #if DEBUG
            if let previewScenario, previewScenario != "picker" { searchText = "oats" }
            #endif
            if let initialFood, !openedInitialFood {
                openedInitialFood = true
                selectedFood = initialFood
            }
        }
        .sheet(item: $selectedFood) { food in
            NavigationStack {
                FoodPortionView(food: food, servingDescription: servingDescription,
                                isSaving: isSaving, error: saveError,
                                lockedForRetry: pendingAdd != nil, onAdd: add)
            }
            .interactiveDismissDisabled(isSaving)
        }
        .sheet(isPresented: $showingSources) { FoodDataSourcesSheet() }
        .onDisappear { cancelProductDetails() }
    }

    private var searchArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Find your food.")
                    .font(.community(.title, weight: .bold))
                    .foregroundStyle(RytivoSunriseDesign.ink)
                Text("Find a food, then choose how much you ate.")
                    .font(.community(.footnote))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { searchInput; searchButton }
                VStack(alignment: .leading, spacing: 8) {
                    searchInput
                    searchButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(8)
            .padding(.leading, 8)
            .background(FoodPickerSurface(fill: RytivoSunriseDesign.surface))

            // Translations and accessibility text sizes may need a full row each.
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) { barcodeAction; manualEntryCard }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { barcodeAction; manualEntryCard }
                    VStack(spacing: 12) { barcodeAction; manualEntryCard }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28)
                .fill(HomeSunriseStyle.backdropGradient)
                .accessibilityHidden(true)
        }
    }

    private var searchInput: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(RepbaseTactileDesign.accentText).accessibilityHidden(true)
            TextField("Search foods or brands", text: $searchText)
                .font(.community(.subheadline))
                .foregroundStyle(RytivoSunriseDesign.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { submitSearch() }
                .frame(minWidth: 100, minHeight: 44)
                .accessibilityIdentifier("food-picker-search")
        }
    }

    private var searchButton: some View {
        Button { submitSearch() } label: {
            Text("Search")
                .font(.community(.footnote, weight: .bold))
                .foregroundStyle(RepbasePalette.ink)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(MealLiftSurface(fill: RepbaseTactileDesign.accent, kind: .primary))
        }
        .buttonStyle(RepbaseTactilePressStyle())
        .disabled(searchText.trimmed.count < 2 || isSaving ||
                  (isSearchingDatabase && submittedQuery == searchText.trimmed))
        .accessibilityIdentifier("food-picker-submit")
    }

    private var barcodeAction: some View {
        Button { cancelProductDetails(); showingBarcode = true } label: {
            FoodPickerActionLabel(title: "Scan barcode", detail: "Packaged foods",
                                  symbol: "barcode.viewfinder", isAccent: true)
        }
        .buttonStyle(RepbaseTactilePressStyle())
        .disabled(isSaving || pendingAdd != nil)
    }

    private var manualEntryCard: some View {
        NavigationLink {
            FoodEntryEditorView(date: date, mealID: mealID) { dismiss() }
        } label: {
            FoodPickerActionLabel(title: "Enter manually", detail: "From the label",
                                  symbol: "square.and.pencil")
        }
        .buttonStyle(RepbaseTactilePressStyle())
        .disabled(isSaving || pendingAdd != nil || loadingCandidateID != nil)
    }

    private var databaseEditorialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FoodPickerSectionHeading(title: "Choose your match") {
                if !isSearchingDatabase && databaseError == nil {
                    Text("\(databaseResults.count) results")
                }
            }
            Text("Tap a food to review its nutrition and portion.")
                .font(.community(.caption)).foregroundStyle(RytivoSunriseDesign.secondary)
            if let databaseError {
                Text(databaseError)
                    .font(.community(.caption))
                    .foregroundStyle(RepbaseTactileDesign.accentText)
                Button("Retry") { searchRevision += 1 }.frame(minHeight: 44)
            } else if isSearchingDatabase {
                ProgressView("Searching…")
                    .font(.community(.subheadline))
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(FoodPickerSurface(fill: HomeSunriseStyle.heroTint))
            } else if databaseResults.isEmpty {
                Text("No complete match found. Try another name or enter the label manually.")
                    .font(.community(.caption))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
            } else {
                ForEach(databaseResults) { result in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { chooseProduct(result) } label: {
                            DatabaseFoodRow(result: result)
                        }
                        .buttonStyle(RepbaseTactilePressStyle())
                        .disabled(isSaving || pendingAdd != nil || loadingCandidateID != nil)
                        if loadingCandidateID == result.id {
                            HStack {
                                ProgressView("Checking nutrition…").font(.community(.caption))
                                Spacer()
                                Button("Cancel") { cancelProductDetails() }.frame(minHeight: 44)
                            }
                        }
                    }
                }
            }
            if let detailError {
                Text(detailError).font(.community(.caption)).foregroundStyle(RepbaseTactileDesign.accentText)
                if pendingCandidate != nil {
                    Button("Retry") {
                        guard let pendingCandidate, loadingCandidateID == nil else { return }
                        loadingCandidateID = pendingCandidate.id
                        detailRevision += 1
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }

    private var recentEditorialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FoodPickerSectionHeading(title: "Have it again") { Text("Recent foods") }
            Text("Your recent foods. Adjust the portion before adding.")
                .font(.community(.caption))
                .foregroundStyle(RytivoSunriseDesign.secondary)
                if filteredRecents.isEmpty {
                    Text(recentEmptyMessage)
                        .font(.community(.subheadline))
                        .foregroundStyle(RytivoSunriseDesign.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    ForEach(filteredRecents) { food in
                        Button {
                            servingDescription = String(localized: "1 serving of this food entry", bundle: .app, locale: .app)
                            selectedFood = food
                        } label: {
                            RecentFoodRow(food: food)
                        }
                        .buttonStyle(RepbaseTactilePressStyle())
                        .disabled(isSaving || pendingAdd != nil || loadingCandidateID != nil)
                    }
                }
        }
    }

    // MARK: - Data

    private var isPreview: Bool {
        #if DEBUG
        previewScenario != nil
        #else
        false
        #endif
    }

    private var filteredRecents: [FoodEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.recentFoods }
        return store.recentFoods.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    private var recentEmptyMessage: LocalizedStringKey {
        store.recentFoods.isEmpty
            ? "Foods you log will show up here so you can add them again in one tap."
            : "No previously used food matches that search."
    }

    /// Adds a copy of a previously used food. A fresh identifier keeps this
    /// entry independent, so editing it never changes the original.
    private func add(_ food: FoodEntry) {
        guard !isSaving else { return }
        #if DEBUG
        if previewScenario != nil {
            savedFood = food
            selectedFood = nil
            return
        }
        #endif
        if let pendingAdd,
           pendingAdd.name != food.name || pendingAdd.servings != food.servings || pendingAdd.nutritionPerServing != food.nutritionPerServing ||
            pendingAdd.sourceID != food.sourceID || pendingAdd.referenceQuantity != food.referenceQuantity ||
            pendingAdd.referenceUnit != food.referenceUnit || pendingAdd.servingDescription != food.servingDescription ||
            pendingAdd.nutrients != food.nutrients {
            saveError = String(
                localized: "Please retry the previous food first so we can confirm whether it saved.",
                bundle: .app,
                locale: .app
            )
            return
        }
        let entry = pendingAdd ?? food.copyForLogging()
        pendingAdd = entry
        isSaving = true
        saveError = nil
        Task {
            defer { isSaving = false }
            let saved = await store.saveFood(
            entry,
            in: mealID,
            on: date
        )
        guard saved else {
            saveError = store.errorMessage ?? SaveFailure.unexplained
            return
        }
        draftSaved = true
        savedFood = entry
        selectedFood = nil
        }
    }

    private func submitSearch() {
        let query = searchText.trimmed
        // Repeated keyboard submits/taps must not cancel the same request
        // and spend another backend/provider rate-limit slot.
        guard !isSaving, query.count >= 2,
              !(isSearchingDatabase && submittedQuery == query) else { return }
        cancelProductDetails()
        submittedQuery = query
        searchRevision += 1
    }

    private func searchDatabase() async {
        #if DEBUG
        if let previewScenario {
            submittedQuery = previewScenario == "picker" ? "" : "oats"
            databaseResults = ["picker-results", "picker-accessibility"].contains(previewScenario)
                ? FoodPickerPreviewFixtures.candidates : []
            isSearchingDatabase = previewScenario == "picker-loading"
            databaseError = previewScenario == "picker-error"
                ? catalogueError(FoodCatalogueFailure.busy, details: false) : nil
            return
        }
        #endif
        let query = submittedQuery
        let revision = searchRevision
        guard query.count >= 2 else {
            databaseResults = []
            databaseError = nil
            isSearchingDatabase = false
            return
        }
        isSearchingDatabase = true
        defer {
            if revision == searchRevision, query == submittedQuery { isSearchingDatabase = false }
        }
        databaseResults = []
        databaseError = nil
        guard !Task.isCancelled else { return }
        do {
            let results = try await store.searchCatalogue(query)
            guard !Task.isCancelled, revision == searchRevision, query == submittedQuery else { return }
            databaseResults = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, revision == searchRevision, query == submittedQuery else { return }
            databaseResults = []
            databaseError = catalogueError(error, details: false)
        }
        isSearchingDatabase = false
    }

    private func chooseProduct(_ candidate: FoodCatalogueCandidate) {
        guard !isSaving, pendingAdd == nil, loadingCandidateID == nil else { return }
        pendingCandidate = candidate
        loadingCandidateID = candidate.id
        detailError = nil
        detailRevision += 1
    }

    private func cancelProductDetails() {
        pendingCandidate = nil
        loadingCandidateID = nil
        detailError = nil
        detailRevision += 1
    }

    private func loadProductDetails() async {
        guard let candidate = pendingCandidate else { return }
        #if DEBUG
        if previewScenario != nil {
            loadingCandidateID = nil
            pendingCandidate = nil
            if let product = FoodPickerPreviewFixtures.detail(for: candidate) {
                servingDescription = product.servingDescription
                selectedFood = product.entry
            } else {
                detailError = String(localized: "Nutrition is incomplete for this product. Check another match or enter the label manually.",
                                     bundle: .app, locale: .app)
            }
            return
        }
        #endif
        let revision = detailRevision
        loadingCandidateID = candidate.id
        detailError = nil
        defer { if revision == detailRevision { loadingCandidateID = nil } }
        do {
            try Task.checkCancellation()
            let product = try await store.catalogueDetails(for: candidate)
            guard !Task.isCancelled, revision == detailRevision,
                  pendingCandidate?.id == candidate.id else { return }
            guard let product else {
                pendingCandidate = nil
                detailError = String(localized: "Nutrition is incomplete for this product. Check another match or enter the label manually.",
                                     bundle: .app, locale: .app)
                return
            }
            servingDescription = product.servingDescription
            pendingCandidate = nil
            selectedFood = product.entry
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, revision == detailRevision,
                  pendingCandidate?.id == candidate.id else { return }
            detailError = catalogueError(error, details: true)
        }
    }

    private func catalogueError(_ error: Error, details: Bool) -> String {
        if let failure = error as? FoodCatalogueFailure {
            switch failure {
            case .busy:
                return String(localized: "Food search is busy. Wait a moment, then retry.", bundle: .app, locale: .app)
            case .sessionExpired:
                return String(localized: "Your session has expired. Sign in again to search foods.", bundle: .app, locale: .app)
            }
        }
        if let response = error as? RepbaseAPIHTTPError {
            if response.statusCode == 429 {
                return String(localized: "Food search is busy. Wait a moment, then retry.", bundle: .app, locale: .app)
            }
            if response.statusCode == 401 {
                return String(localized: "Your session has expired. Sign in again to search foods.", bundle: .app, locale: .app)
            }
        }
        if details {
            return String(localized: "Could not load this food’s nutrition. Please retry.", bundle: .app, locale: .app)
        }
        return String(localized: "The food database could not be reached. You can still reuse or enter a food manually.",
                      bundle: .app, locale: .app)
    }
}

/// Portion selection changes only the quantity; saving still uses the picker's
/// existing retry-safe save path and a fresh entry identity.
private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// A catalogue row.
///
/// Says what the numbers are measured against, which the recents row has no
/// need to: a food logged before carries the serving it was logged with, while
/// catalogue products may be per 100 g, 100 ml, or a labelled serving. Adding one without
/// reading that is how a chicken breast gets logged as a third of itself.
private struct DatabaseFoodRow: View {
    let result: FoodCatalogueCandidate

    var body: some View {
        FoodPickerMatchLabel(name: result.name) {
            if let verified = result.verifiedResult {
                Text("Per \(verified.servingDescription)")
            } else if !result.brand.isEmpty {
                Text(result.brand)
            }
        } value: {
            if let verified = result.verifiedResult {
                Text("\(verified.entry.totalNutrition.calories.nutritionText) kcal")
            } else {
                Text("Details")
            }
        }
    }
}

private struct RecentFoodRow: View {
    let food: FoodEntry

    var body: some View {
        FoodPickerMatchLabel(name: food.name, isRecent: true) {
            Text("Last logged portion")
        } value: {
            Text("\(food.totalNutrition.calories.nutritionText) kcal")
        }
    }
}

#Preview {
    let store = FoodTrackingStore.preview
    let meal = store.meals(on: Date())[0]
    NavigationStack {
        FoodPickerView(date: Date(), mealID: meal.id)
    }
    .environment(store)
}
