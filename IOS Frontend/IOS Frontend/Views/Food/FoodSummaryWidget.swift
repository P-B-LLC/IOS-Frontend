//
//  FoodSummaryWidget.swift
//  IOS Frontend
//
//  Compact home widget: calories plus three circular macro gauges.
//

import SwiftUI

struct FoodSummaryWidget: View {
    @Environment(FoodTrackingStore.self) private var store

    var body: some View {
        NavigationLink {
            FoodTrackingView()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orange)
                    Text("Food Today")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 6) {
                    HomeCalorieTotal(
                        value: total.calories,
                        goal: store.goals.calories
                    )
                    HomeMacroGauge(
                        title: "Protein",
                        value: total.proteinGrams,
                        goal: store.goals.proteinGrams,
                        color: .blue
                    )
                    HomeMacroGauge(
                        title: "Carbs",
                        value: total.carbohydrateGrams,
                        goal: store.goals.carbohydrateGrams,
                        color: .teal
                    )
                    HomeMacroGauge(
                        title: "Fat",
                        value: total.fatGrams,
                        goal: store.goals.fatGrams,
                        color: .purple
                    )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .shadow(color: .black.opacity(0.035), radius: 6, y: 2)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.045), lineWidth: 0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Food today, \(total.calories.nutritionText) of \(store.goals.calories.nutritionText) calories"
        )
        .accessibilityHint("Opens food tracking")
    }

    private var total: NutritionAmount {
        store.total(on: Date())
    }
}

private struct HomeCalorieTotal: View {
    let value: Decimal
    let goal: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.nutritionText)
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text("of \(goal.nutritionText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("CALORIES")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.orange)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .center)
        .padding(.horizontal, 7)
        .background(Color.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct HomeMacroGauge: View {
    let title: String
    let value: Decimal
    let goal: Decimal
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(value.nutritionText)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 42, height: 42)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
    }

    private var progress: CGFloat {
        guard goal > 0 else { return 0 }
        return min(max(value.nutritionDouble / goal.nutritionDouble, 0), 1)
    }
}

#Preview {
    NavigationStack {
        FoodSummaryWidget()
            .padding()
    }
    .environment(FoodTrackingStore.preview)
}
