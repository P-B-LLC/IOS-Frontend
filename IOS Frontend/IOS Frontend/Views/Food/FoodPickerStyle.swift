import SwiftUI

/// Scoped food-search surfaces; the rest of the app keeps its existing styling.
struct FoodPickerSurface: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    let fill: Color
    var accented = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        shape.fill(fill)
            .overlay { shape.fill(MealLiftGloss(opacity: scheme == .dark ? 0.16 : 0.22)) }
            .overlay {
                shape.strokeBorder(
                    contrast == .increased ? RytivoSunriseDesign.ink
                        : (accented ? RepbaseTactileDesign.accentText : RytivoSunriseDesign.border),
                    lineWidth: contrast == .increased ? 1.5 : 0.75
                )
            }
            .shadow(color: RepbasePalette.ink.opacity(scheme == .dark ? 0.16 : 0.07), radius: 5, y: 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct FoodPickerActionLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    var isAccent = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.community(.title3))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.community(.footnote, weight: .semibold))
                Text(detail)
                    .font(.community(.caption))
                    .foregroundStyle(isAccent ? RepbasePalette.ink : RytivoSunriseDesign.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(isAccent ? RepbasePalette.ink : RytivoSunriseDesign.ink)
        .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(FoodPickerSurface(
            fill: isAccent ? RepbaseTactileDesign.accent : RytivoSunriseDesign.surface,
            accented: isAccent
        ))
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}

struct FoodPickerSectionHeading<Detail: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                heading.fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: 0)
                context.fixedSize(horizontal: true, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) { heading; context }
        }
    }

    private var heading: some View {
        Text(title).font(.community(.headline, weight: .bold))
            .foregroundStyle(RytivoSunriseDesign.ink).accessibilityAddTraits(.isHeader)
    }

    private var context: some View {
        detail().font(.community(.caption)).foregroundStyle(RytivoSunriseDesign.secondary)
    }
}

/// A whole-card selection target. Unknown nutrition is supplied as “Details,”
/// while confirmed values always travel with their serving/reference basis.
struct FoodPickerMatchLabel<Detail: View, Value: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let name: String
    var isRecent = false
    @ViewBuilder let detail: () -> Detail
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(spacing: 10) {
            if isRecent {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.community(.subheadline))
                    .foregroundStyle(RepbaseTactileDesign.accentText)
                    .accessibilityHidden(true)
            }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { information; trailingValue }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                information.frame(maxWidth: .infinity, alignment: .leading)
                trailingValue.fixedSize(horizontal: true, vertical: true)
            }
            Image(systemName: "chevron.forward")
                .font(.community(.caption))
                .foregroundStyle(RepbaseTactileDesign.accentText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(FoodPickerSurface(fill: RepbaseTactileDesign.cardTint))
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.community(.body, weight: .bold))
                .foregroundStyle(RytivoSunriseDesign.ink)
            detail().font(.community(.caption)).foregroundStyle(RytivoSunriseDesign.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var trailingValue: some View {
        value().font(.community(.caption, weight: .semibold))
            .foregroundStyle(RepbaseTactileDesign.accentText)
    }
}

struct FoodDataSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Contains information from Open Food Facts, available under the Open Database License (ODbL).")
                        .font(.community(.body))
                    Text("Community entries can be incomplete. Check the label and your portion before logging.")
                        .font(.community(.footnote))
                    Link(destination: URL(string: "https://world.openfoodfacts.org")!) {
                        Text("Open Food Facts").underline()
                    }
                    Link(destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!) {
                        Text("Open Database License").underline()
                    }
                }
                .foregroundStyle(RytivoSunriseDesign.secondary)
                .padding(24)
            }
            .navigationTitle("Food data & sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
            .tint(RepbaseTactileDesign.accentText)
            .background(Color(.systemBackground))
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Native previews never load, write or clear an account's recoverable draft.
/// Production keeps exactly the same key, bindings and retry identity.
struct FoodPickerDraftRecovery: ViewModifier {
    let enabled: Bool
    let mealID: FoodMeal.ID
    @Binding var pendingAdd: FoodEntry?
    @Binding var saved: Bool
    @Binding var error: String?

    func body(content: Content) -> some View {
        if enabled {
            content.recoverableDraft(key: "food-picker-\(mealID)", value: $pendingAdd,
                                     saved: $saved, error: $error)
        } else {
            content
        }
    }
}
