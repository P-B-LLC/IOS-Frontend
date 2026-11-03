import SwiftUI

struct FoodPortionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var amountFocused: Bool
    let food: FoodEntry
    let servingDescription: String
    let isSaving: Bool
    let error: String?
    let lockedForRetry: Bool
    let onAdd: (FoodEntry) -> Void
    @State private var quantity: String
    @State private var usesMeasurement: Bool
    @State private var usesOunces = false
    @State private var showsNutrients = false

    init(food: FoodEntry, servingDescription: String, isSaving: Bool,
         error: String?, lockedForRetry: Bool, onAdd: @escaping (FoodEntry) -> Void) {
        self.food = food
        self.servingDescription = food.servingDescription ?? servingDescription
        self.isSaving = isSaving
        self.error = error
        self.lockedForRetry = lockedForRetry
        self.onAdd = onAdd
        let reference = FoodPortionReference(quantity: food.referenceQuantity, unit: food.referenceUnit,
                                              legacyDescription: food.servingDescription ?? servingDescription)
        let measured = reference != nil
        _usesMeasurement = State(initialValue: measured)
        _quantity = State(initialValue: (food.servings * (reference?.quantity ?? 1))
            .formatted(.number.locale(.app).precision(.fractionLength(0...12)).grouping(.never)))
    }

    private var servings: Decimal? {
        guard let value = FoodPortionMeasurement.positive(quantity, locale: .app) else { return nil }
        guard let multiplier = FoodPortionMeasurement.multiplier(amount: value, measured: usesMeasurement,
            ounces: usesOunces && !isLiquid, gramsPerServing: measurementBasis) else { return nil }
        return FoodPortionMeasurement.savedMultiplier(multiplier)
    }
    private var reference: FoodPortionReference? {
        FoodPortionReference(quantity: food.referenceQuantity, unit: food.referenceUnit,
                             legacyDescription: servingDescription)
    }
    private var isLiquid: Bool { reference?.unit == "ml" }
    private var measurementBasis: Decimal? { reference?.quantity }
    private var measurementFactor: Decimal? {
        guard usesMeasurement else { return 1 }
        guard let basis = measurementBasis else { return nil }
        return basis / (usesOunces && !isLiquid ? FoodPortionMeasurement.gramsPerOunce : 1)
    }
    private var nutrition: NutritionAmount { food.nutritionPerServing * (servings ?? 0) }

    var body: some View {
        VStack(spacing: 0) {
            if !typeSize.isAccessibilitySize { foodHeading }
            ScrollView {
                VStack(spacing: 0) {
                    if typeSize.isAccessibilitySize {
                        foodHeading.background(HomeSunriseStyle.backdrop)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        if servings != nil {
                            FoodPortionMacroSummary(nutrition: nutrition)
                        } else {
                            Text("Enter an amount to see nutrition.")
                                .font(.community(.subheadline))
                                .foregroundStyle(RytivoSunriseDesign.secondary)
                        }
                        portionControls
                        if let servings { nutrientDetails(servings) }
                    }
                    .padding(24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(RepbaseTactileSheetBackground())
            .safeAreaInset(edge: .bottom, spacing: 0) { addFooter }
        }
        .foregroundStyle(RytivoSunriseDesign.ink)
        .background {
            HomeSunriseStyle.backdrop
                .overlay { Rectangle().fill(MealLiftGloss(opacity: scheme == .dark ? 0.10 : 0.36)) }
                .ignoresSafeArea()
        }
        .tint(RepbaseTactileDesign.accentText)
        .navigationTitle("Portion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back to results") { dismiss() }.disabled(isSaving)
            }
        }
    }

    private var foodHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nice find.")
                .font(.community(.caption, weight: .semibold))
                .foregroundStyle(RytivoSunriseDesign.secondary)
            Text(food.name)
                .font(.community(size: 28, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Make it your portion.")
                .font(.community(.subheadline))
                .foregroundStyle(RytivoSunriseDesign.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    private var portionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if reference != nil {
                Picker("Portion", selection: Binding(get: { usesMeasurement }, set: { selected in
                    let previous = servings
                    usesMeasurement = selected
                    restoreQuantity(previous)
                })) {
                    if isLiquid { Text("Millilitres").tag(true) }
                    else { Text("Weight").tag(true) }
                    Text("Servings").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
            }
            if usesMeasurement && !isLiquid {
                Picker("Weight", selection: Binding(get: { usesOunces }, set: { selected in
                    let previous = servings
                    usesOunces = selected
                    restoreQuantity(previous)
                })) {
                    Text("Grams").tag(false)
                    Text("Ounces").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
            }
            quantityRow
            if let reference {
                Text("1 serving = \(reference.quantity.formatted(.number.locale(.app).precision(.fractionLength(0...4)).grouping(.never))) \(reference.unit)")
                    .font(.community(.caption))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
            }
            Text("Per serving: \(servingDescription)")
                .font(.community(.caption))
                .foregroundStyle(RytivoSunriseDesign.secondary)
            if reference == nil {
                Text("Weight not verified. Use servings.")
                    .font(.community(.caption2, weight: .semibold))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
                    .accessibilityHint("This food has no verified weight or volume. Use servings, or choose a database match.")
            }
        }
        .padding(14)
        .background(MealLiftSurface(fill: RytivoSunriseDesign.surface, radius: 24))
        .disabled(isSaving || lockedForRetry)
    }

    private var quantityRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your portion").font(.community(.headline))
                Text(portionUnit)
                    .font(.community(.caption))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                TextField("Quantity", text: $quantity)
                    .keyboardType(.decimalPad)
                    .font(.community(size: 24, weight: .bold))
                    .textFieldStyle(.plain)
                    .focused($amountFocused)
                    .accessibilityLabel(portionUnit)
                    .accessibilityIdentifier("portion.quantity")
                Image(systemName: "pencil")
                    .font(.system(size: 15))
                    .foregroundStyle(RepbaseTactileDesign.accentText)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(width: typeSize.isAccessibilitySize ? nil : 142)
            .frame(minHeight: 56)
            .background(MealLiftSurface(fill: HomeSunriseStyle.heroTint, kind: .control, radius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                if !isSaving && !lockedForRetry { amountFocused = true }
            }
        }
    }

    private func nutrientDetails(_ servings: Decimal) -> some View {
        DisclosureGroup(isExpanded: $showsNutrients) {
            FoodNutrientsList(entries: [portionEntry(servings)], showsCoverage: false)
                .padding(.top, 12)
            FoodDailyValueFootnote().padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("More nutrition")
                    .font(.community(.headline))
                    .foregroundStyle(RytivoSunriseDesign.ink)
                Text("Vitamins, minerals & more")
                    .font(.community(.caption))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
            }
            .frame(minHeight: 44, alignment: .leading)
        }
        .padding(14)
        .background(RytivoSunriseDesign.surface,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(RytivoSunriseDesign.border, lineWidth: 0.75)
        }
    }

    private var addFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error {
                Text(error).foregroundStyle(.red).accessibilityAddTraits(.isStaticText)
            }
            if servings == nil {
                Text("Check the portion quantity.")
                    .font(.community(.caption))
                    .foregroundStyle(RytivoSunriseDesign.secondary)
            }
            Button {
                guard let servings else { return }
                var entry = food
                entry.servings = servings
                onAdd(entry)
            } label: {
                HStack(spacing: 10) {
                    if isSaving { ProgressView().tint(RepbasePalette.ink) }
                    else if !lockedForRetry { Image(systemName: "plus").accessibilityHidden(true) }
                    Text(isSaving ? "Saving…" : lockedForRetry ? "Retry adding food" : "Add to meal")
                        .font(.community(.headline))
                }
                .foregroundStyle(RepbasePalette.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(MealLiftSurface(fill: RepbaseTactileDesign.accent, kind: .primary))
                .contentShape(Capsule())
            }
            .buttonStyle(RepbaseTactilePressStyle())
            .disabled(isSaving || servings == nil)
            .accessibilityIdentifier("portion.add")
            Text("You can edit the portion later.")
                .font(.community(.caption))
                .foregroundStyle(RytivoSunriseDesign.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(RytivoSunriseDesign.surface.ignoresSafeArea(edges: .bottom))
    }

    private func restoreQuantity(_ previous: Decimal?) {
        guard let previous, let factor = measurementFactor else {
            quantity = ""
            return
        }
        quantity = (previous * factor).formatted(.number.locale(.app).precision(.fractionLength(0...12)).grouping(.never))
    }

    private func portionEntry(_ servings: Decimal) -> FoodEntry {
        var entry = food
        entry.servings = servings
        return entry
    }

    private var portionUnit: LocalizedStringKey {
        if !usesMeasurement { return "Servings" }
        if isLiquid { return "Millilitres" }
        return usesOunces ? "Ounces" : "Grams"
    }
}

#if DEBUG
/// Isolated visual fixtures for the existing simulator-capture harness.
/// No account, API client, or save operation is used by these previews.
struct FoodPortionPreview: View {
    let scenario: String

    var body: some View {
        FoodPortionView(
            food: previewFood,
            servingDescription: previewFood.servingDescription ?? "",
            isSaving: scenario == "portion-saving",
            error: scenario == "portion-retry"
                ? String(localized: "Couldn't reach Rytivo. Check your connection and try again.", bundle: .app, locale: .app)
                : nil,
            lockedForRetry: scenario == "portion-retry",
            onAdd: { _ in }
        )
        .dynamicTypeSize(scenario == "portion-accessibility" ? .accessibility3 : .large)
    }

    private var previewFood: FoodEntry {
        switch scenario {
        case "portion-weight":
            FoodEntry(name: "Chicken breast", servings: Decimal(string: "1.25")!,
                      nutritionPerServing: NutritionAmount(calories: 165, proteinGrams: 31,
                                                           carbohydrateGrams: 0, fatGrams: Decimal(string: "3.6")!),
                      servingDescription: "100 g", referenceQuantity: 100, referenceUnit: "g")
        case "portion-liquid":
            FoodEntry(name: "Milk", nutritionPerServing: NutritionAmount(
                calories: 125, proteinGrams: 8, carbohydrateGrams: 12, fatGrams: 5),
                      servingDescription: "250 ml", referenceQuantity: 250, referenceUnit: "ml")
        case "portion-zero":
            FoodEntry(name: "Sparkling water", nutritionPerServing: .zero,
                      servingDescription: "1 glass")
        default:
            FoodEntry(name: "Coco Pops · Kellogg’s",
                      servings: scenario == "portion-large" ? Decimal(string: "1.5")! : 1,
                      nutritionPerServing: NutritionAmount(calories: 386, proteinGrams: Decimal(string: "6.3")!,
                                                           carbohydrateGrams: 84, fatGrams: Decimal(string: "1.9")!),
                      servingDescription: "1 serving (100 g)")
        }
    }
}
#endif
