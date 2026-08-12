//
//  FoodSummaryWidget.swift
//  IOS Frontend
//
//  Compact home entry point for today's calories and macronutrients.
//

import SwiftUI

struct FoodSummaryWidget: View {
    @Environment(FoodTrackingStore.self) private var store

    var body: some View {
        NavigationLink {
            FoodTrackingView()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
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

                HStack(spacing: 16) {
                    CalorieProgressRing(
                        consumed: total.calories,
                        goal: store.goals.calories,
                        size: 76,
                        lineWidth: 9
                    )

                    HStack(spacing: 8) {
                        CompactMacro(
                            title: "Protein",
                            value: total.proteinGrams,
                            goal: store.goals.proteinGrams,
                            color: .blue
                        )
                        CompactMacro(
                            title: "Carbs",
                            value: total.carbohydrateGrams,
                            goal: store.goals.carbohydrateGrams,
                            color: .green
                        )
                        CompactMacro(
                            title: "Fat",
                            value: total.fatGrams,
                            goal: store.goals.fatGrams,
                            color: .purple
                        )
                    }
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
    }

    private var total: NutritionAmount {
        store.total(on: Date())
    }
}

struct CalorieProgressRing: View {
    let consumed: Decimal
    let goal: Decimal
    var size: CGFloat = 112
    var lineWidth: CGFloat = 13

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.orange.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.orange,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(consumed.nutritionText)
                    .font(size > 90 ? .title2.weight(.bold) : .subheadline.weight(.bold))
                Text("of \(goal.nutritionText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if size > 90 {
                    Text("CAL")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private var progress: CGFloat {
        guard goal > 0 else { return 0 }
        return min(max(consumed.nutritionDouble / goal.nutritionDouble, 0), 1)
    }
}

private struct CompactMacro: View {
    let title: String
    let value: Decimal
    let goal: Decimal
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value.nutritionText)
                    .font(.caption2.weight(.bold))
            }
            .frame(width: 44, height: 44)
            Text("/ \(goal.nutritionText)g")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
