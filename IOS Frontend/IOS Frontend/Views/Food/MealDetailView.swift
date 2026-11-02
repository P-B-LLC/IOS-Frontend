//
//  MealDetailView.swift
//  IOS Frontend
//
//  One meal's complete logging workspace.
//

import SwiftUI

struct MealDetailView: View {
    @Environment(FoodTrackingStore.self) private var store
    @Environment(BottomBarChrome.self) private var bottomBar: BottomBarChrome?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var recentCardWidth: CGFloat = 171

    let date: Date
    let mealID: FoodMeal.ID

    /// The existing saved-meal destination uses the day's one-based slot.
    private var mealNumber: Int? {
        store.meals(on: date)
            .firstIndex { $0.id == mealID }
            .map { $0 + 1 }
    }

    @State private var isAddingFood = false
    @State private var isEnteringFood = false
    @State private var isShowingSavedMeals = false
    @State private var editingFood: FoodEntry?
    @State private var isRenamingMeal = false
    @State private var renamedMeal = ""
    @State private var showsNutritionDetails = false
    @State private var recentFoodSelection: FoodEntry?

    var body: some View {
        Group {
            if let meal {
                mealWorkspace(meal)
                    .navigationTitle(meal.displayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbar { mealToolbar(meal) }
            } else {
                ContentUnavailableView(
                    "Meal Not Found",
                    systemImage: "fork.knife",
                    description: Text("This meal may have been removed.")
                )
            }
        }
        .tint(RepbaseTactileDesign.accentText)
        .fullScreenCover(isPresented: $isAddingFood) {
            NavigationStack {
                FoodPickerView(date: date, mealID: mealID, initialFood: recentFoodSelection)
            }
        }
        .fullScreenCover(isPresented: $isEnteringFood) {
            NavigationStack {
                FoodEntryEditorView(date: date, mealID: mealID)
            }
        }
        .fullScreenCover(isPresented: $isShowingSavedMeals) {
            NavigationStack {
                SavedMealsView(
                    referenceDate: date,
                    destination: mealNumber.map {
                        SavedMealsView.Destination(date: date, mealNumber: $0)
                    }
                )
            }
        }
        .fullScreenCover(item: $editingFood) { food in
            NavigationStack {
                FoodEntryEditorView(date: date, mealID: mealID, existing: food)
            }
        }
        .alert("Rename Meal", isPresented: $isRenamingMeal) {
            TextField("Meal name", text: $renamedMeal)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                store.renameMeal(id: mealID, to: renamedMeal, on: date)
            }
        }
    }

    private func mealWorkspace(_ meal: FoodMeal) -> some View {
        VStack(spacing: 0) {
            mealIntroduction(meal)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    addFoodActions
                    if !meal.entries.isEmpty {
                        mealSummary(meal)
                        foodList(meal)
                    }
                    if !store.recentFoods.isEmpty { recentFoodShelf }
                    if !meal.entries.isEmpty {
                        DisclosureGroup("Nutrition details", isExpanded: $showsNutritionDetails) {
                            NutritionBreakdownView(meals: [meal], scope: .meal)
                                .padding(.top, 12)
                        }
                        .font(.community(.subheadline, weight: .semibold))
                    }
                }
                .padding(RepbaseTactileDesign.pageInset)
            }
            .background(RepbaseTactileSheetBackground())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                mealFooter
            }
        }
        .foregroundStyle(RytivoSunriseDesign.ink)
        .background {
            HomeSunriseStyle.backdrop
                .overlay { Rectangle().fill(MealLiftGloss(opacity: 0.36)) }
                .ignoresSafeArea()
        }
    }

    private func mealIntroduction(_ meal: FoodMeal) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(meal.entries.isEmpty ? "Build your plate." : "Your plate, your way.")
                    .font(.community(.title2, weight: .bold))
                Text(meal.entries.isEmpty
                     ? "One ingredient at a time."
                     : "Add more, or adjust your portions.")
                    .font(.community(.subheadline))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize { MealPlateIllustration() }
        }
        .padding(.horizontal, RepbaseTactileDesign.pageInset)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var addFoodActions: some View {
        VStack(spacing: 12) {
            Button {
                recentFoodSelection = nil
                isAddingFood = true
            } label: {
                Label("Search foods", systemImage: "magnifyingglass")
                    .font(.community(.headline))
                    .foregroundStyle(RepbasePalette.ink)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(MealLiftSurface(fill: RepbaseTactileDesign.accent, kind: .primary))
                    .contentShape(Capsule())
            }
            .accessibilityIdentifier("meal.search")

            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                mealActionTile("Cookbooks", detail: "Use a saved recipe",
                               symbol: "books.vertical", isWarm: true) {
                    isShowingSavedMeals = true
                }
                .accessibilityIdentifier("meal.cookbooks")
                mealActionTile("Enter manually", detail: "Add from a label",
                               symbol: "square.and.pencil", isWarm: false) {
                    isEnteringFood = true
                }
                .accessibilityIdentifier("meal.manual")
            }
        }
        .buttonStyle(RepbaseTactilePressStyle())
    }

    private func mealActionTile(
        _ title: LocalizedStringKey, detail: LocalizedStringKey,
        symbol: String, isWarm: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 21))
                    .foregroundStyle(RepbaseTactileDesign.accentText)
                    .frame(width: 42, height: 42)
                    .background(MealLiftSurface(
                        fill: isWarm ? RytivoSunriseDesign.surface : HomeSunriseStyle.heroTint,
                        kind: .control, radius: 14
                    ))
                    .accessibilityHidden(true)
                Text(title).font(.community(.headline))
                Text(detail)
                    .font(.community(.caption))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(16)
            .background(MealLiftSurface(
                fill: isWarm ? HomeSunriseStyle.heroTint : RytivoSunriseDesign.surface
            ))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private func mealSummary(_ meal: FoodMeal) -> some View {
        let nutrition = meal.totalNutrition
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meal total")
                        .font(.community(.caption))
                        .foregroundStyle(RytivoSunriseDesign.secondary)
                    Text("\(nutrition.calories.nutritionText) kcal")
                        .font(.community(.title2, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text("\(meal.entries.count) foods")
                    .font(.community(.caption))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                ForEach(Macro.allCases) { macro in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(macro.title)
                            .font(.community(.caption2, weight: .semibold))
                            .foregroundStyle(RytivoSunriseDesign.secondary)
                        Text("\(macro.grams(in: nutrition).nutritionText) g")
                            .font(.community(.headline))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MealLiftSurface(fill: HomeSunriseStyle.heroTint))
    }

    private var recentFoodShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Have it again").font(.community(.headline))
                Text("Your recently logged foods.")
                    .font(.community(.caption))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(store.recentFoods.prefix(8)) { food in
                        Button {
                            recentFoodSelection = food
                            isAddingFood = true
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(food.name)
                                    .font(.community(.subheadline, weight: .semibold))
                                MealFoodQuantity(food: food)
                                // A label inside the existing whole-card button.
                                MealCompactActionLabel(title: "Choose portion", symbol: "plus")
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: recentCardWidth - 32, alignment: .leading)
                            .frame(minHeight: 124, alignment: .topLeading)
                            .padding(16)
                            .background(MealLiftSurface(fill: RytivoSunriseDesign.surface))
                            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        }
                        .buttonStyle(RepbaseTactilePressStyle())
                    }
                }
                // Keep shadows inside the horizontal scroll view's bounds.
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
                .padding(.top, 4)
            }
            .padding(.horizontal, -12)
        }
    }

    private func foodList(_ meal: FoodMeal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On your plate").font(.community(.headline))
            ForEach(meal.entries) { food in
                Button {
                    editingFood = food
                } label: {
                    MealFoodEntryLabel(food: food)
                }
                .buttonStyle(RepbaseTactilePressStyle())
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        store.removeFood(id: food.id, from: mealID, on: date)
                    }
                }
            }
        }
    }

    private var mealFooter: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        return layout {
            Text("Foods save as you add them.")
                .font(.community(.caption))
                .foregroundStyle(RytivoSunriseDesign.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { dismiss() } label: {
                MealCompactActionLabel(title: "Done", symbol: "checkmark", isDone: true)
            }
            .buttonStyle(RepbaseTactilePressStyle())
            .accessibilityIdentifier("meal.done")
        }
        .padding(.horizontal, RepbaseTactileDesign.pageInset)
        .padding(.vertical, 12)
        // The shell's floating bar is outside this navigation stack. Reserve
        // the same clearance as the other Training pages, not inside the scroll.
        .padding(.bottom, bottomBar == nil ? 0 : RepbaseDesign.bottomBarClearance)
        .background(RytivoSunriseDesign.surface.ignoresSafeArea(edges: .bottom))
    }

    @ToolbarContentBuilder
    private func mealToolbar(_ meal: FoodMeal) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Rename Meal", systemImage: "pencil") {
                    renamedMeal = meal.name
                    isRenamingMeal = true
                }
                Button("Remove Meal", systemImage: "trash", role: .destructive) {
                    store.removeMeal(id: mealID, on: date)
                    dismiss()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Meal options")
        }
    }

    private var meal: FoodMeal? {
        store.meals(on: date).first { $0.id == mealID }
    }
}

private struct MealFoodQuantity: View {
    let food: FoodEntry

    var body: some View {
        Text(food.servings == 1
             ? "\(food.servings.nutritionText) serving · \(food.totalNutrition.calories.nutritionText) kcal"
             : "\(food.servings.nutritionText) servings · \(food.totalNutrition.calories.nutritionText) kcal")
            .font(.community(.caption))
            .foregroundStyle(RytivoSunriseDesign.secondary)
    }
}

private struct MealFoodEntryLabel: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let food: FoodEntry

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(food.name).font(.community(.headline))
                MealFoodQuantity(food: food)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            MealCompactActionLabel(title: "Edit", symbol: "pencil")
        }
        .frame(minHeight: 54)
        .padding(16)
        .background(MealLiftSurface(fill: RytivoSunriseDesign.surface))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

#Preview {
    let store = FoodTrackingStore.preview
    let meal = store.meals(on: Date())[0]
    NavigationStack {
        MealDetailView(date: Date(), mealID: meal.id)
    }
    .environment(store)
}
