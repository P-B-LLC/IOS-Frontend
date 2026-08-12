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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(Color.orange)
                    Text("Food Today")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
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
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
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
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text("of \(goal.nutritionText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("CALORIES")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.orange)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .center)
        .padding(.horizontal, 8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct HomeMacroGauge: View {
    let title: String
    let value: Decimal
    let goal: Decimal
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(value.nutritionText)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 50, height: 50)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
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
