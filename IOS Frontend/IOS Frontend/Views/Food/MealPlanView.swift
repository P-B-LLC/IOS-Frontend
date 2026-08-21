//
//  MealPlanView.swift
//  IOS Frontend
//
//  Assembling a day of meals before committing to it.
//
//  The plan is a local draft and nothing else until Apply is pressed. Adding a
//  meal here writes nothing, removing one writes nothing, and leaving the
//  screen writes nothing — the day on the food page is untouched until the
//  user says so.
//

import SwiftUI

struct MealPlanView: View {
    /// The day the plan opens on. Which day it is written to is the user's to
    /// choose here, rather than being inherited silently from whatever the
    /// food page happened to be showing.
    let initialDate: Date

    @Environment(FoodTrackingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date

    /// The draft. Saved meals in the order they would occupy the day, so the
    /// first is meal one. Held here and nowhere else.
    @State private var plan: [SavedFoodMeal] = []
    @State private var isApplying = false
    @State private var outcome: FoodTrackingStore.PlanOutcome?

    init(initialDate: Date) {
        self.initialDate = initialDate
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RepbaseScreenHeader(
                    eyebrow: "MEAL PLANNER",
                    title: "Shape the day.",
                    detail: "Build a draft, review its balance, then apply it when it feels right."
                )
                daySummary
                plannedSection
                if let outcome { report(outcome) }
                library
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .repbaseScreen(.prepare)
        .navigationTitle("Plan meals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply to day") {
                    Task { await apply() }
                }
                // Guarded rather than merely discouraged: a second tap while
                // the first is in flight would write every meal twice.
                .disabled(plan.isEmpty || isApplying || store.isSaving)
            }
        }
        // No fetch here. Saved meals are read once when the account connects
        // and SavedMealsView reads the same list without refetching; asking
        // again on open would be a request for something already in hand.
    }

    // MARK: - Totals

    private var daySummary: some View {
        let total = plan.reduce(NutritionAmount.zero) { $0 + $1.totalNutrition }
        return VStack(alignment: .leading, spacing: 14) {
            DatePicker("Apply to", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(.subheadline.weight(.semibold))
                .accessibilityHint("The day this plan will be written to")

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.isEmpty ? "START WITH A SAVED MEAL" : "DAY IN PROGRESS")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(RepbasePalette.caramel)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(total.calories.nutritionText)
                            .font(.largeTitle.weight(.bold))
                            .contentTransition(.numericText())
                        Text("kcal")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(plan.count) \(plan.count == 1 ? "meal" : "meals")")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(RepbasePalette.oatmeal, in: Capsule())
            }

            // Every figure comes from the saved meals the server holds; none
            // of it is typed in here.
            HStack(spacing: 10) {
                macro("Protein", total.proteinGrams, color: Color(hex: 0xD9824B))
                macro("Carbs", total.carbohydrateGrams, color: Color(hex: 0x4AAFB3))
                macro("Fat", total.fatGrams, color: Color(hex: 0xB76AA5))
            }

            Text("Nothing is saved until you apply this to the day.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func macro(_ title: String, _ value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(value.nutritionText) g")
                .font(.subheadline.weight(.bold).monospacedDigit())
            Capsule().fill(color).frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The draft

    @ViewBuilder
    private var plannedSection: some View {
        if plan.isEmpty {
            Text("Add saved meals below to build a day.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("PLANNED DAY")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(RepbasePalette.caramel)
                    .padding(.bottom, 8)

                ForEach(Array(plan.enumerated()), id: \.offset) { index, meal in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .frame(width: 22, height: 22)
                            .foregroundStyle(RepbasePalette.caramel)
                            .background(RepbasePalette.caramel.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(meal.name).font(.subheadline.weight(.semibold))
                            Text("\(meal.totalNutrition.calories.nutritionText) kcal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Button {
                            plan.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(meal.name) from the plan")
                    }
                    .padding(.vertical, 4)
                    if index < plan.count - 1 { Divider().padding(.leading, 32).opacity(0.45) }
                }
            }
        }
    }

    // MARK: - What can be added

    @ViewBuilder
    private var library: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SAVED MEALS")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(RepbasePalette.caramel)

            if store.savedMeals.isEmpty {
                Text("No saved meals yet. Save a meal from a day to reuse it here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(store.savedMeals.enumerated()), id: \.element.id) { index, meal in
                    Button {
                        plan.append(meal)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(meal.name).font(.subheadline.weight(.semibold))
                                Text("\(meal.totalNutrition.calories.nutritionText) kcal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "plus.circle.fill")
                                .font(.body)
                                .foregroundStyle(RepbasePalette.caramel)
                        }
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(meal.name) to the plan")
                    .accessibilityHint("Adds it as meal \(plan.count + 1) of the planned day")
                    if index < store.savedMeals.count - 1 { Divider().opacity(0.45) }
                }
            }
        }
    }

    // MARK: - Applying

    /// Says what happened, per meal.
    private func report(_ outcome: FoodTrackingStore.PlanOutcome) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if outcome.isCompleteSuccess {
                Text("Added \(outcome.applied.count) \(outcome.applied.count == 1 ? "meal" : "meals") to the day.")
                    .font(.footnote.weight(.semibold))
            } else {
                // Names, not a count. "2 of 4 saved" leaves the user to work
                // out which two, on a day they cannot see from here.
                if !outcome.applied.isEmpty {
                    Text("Added: \(outcome.applied.joined(separator: ", "))")
                        .font(.footnote)
                }
                if !outcome.failed.isEmpty {
                    Text("Not added: \(outcome.failed.joined(separator: ", "))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if let message = outcome.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .repbaseDepthSurface(cornerRadius: 14)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func apply() async {
        guard !plan.isEmpty, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        let slots = plan.enumerated().map { (meal: $0.element, number: $0.offset + 1) }
        let result = await store.applyPlan(slots, to: date)
        outcome = result

        // Only a clean run closes. A partial one stays open with the report on
        // screen, so what did not land is still in the draft to try again.
        if result.isCompleteSuccess {
            plan = []
            dismiss()
        } else {
            plan = plan.filter { result.failed.contains($0.name) }
        }
    }
}
