//
//  GearView.swift
//  IOS Frontend
//
//  Shoes and bikes, and how far each has been.
//

import SwiftUI

struct GearView: View {
    /// Set when the list was opened to choose gear for a session rather than
    /// to browse it. Carries what is chosen now and what to do with a new
    /// answer; without it the list is just a list.
    struct Selection {
        let kind: GearKind
        let currentID: Int?
        let choose: (Int?) -> Void
    }

    var selection: Selection?

    @Environment(GearStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kind: GearKind = .shoe
    @State private var editing: GearEditorView.Mode?
    @State private var didFocusKind = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Kind", selection: $kind) {
                    ForEach(GearKind.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if let error = store.persistenceError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let items = store.all(kind)
                if items.isEmpty {
                    emptyState
                } else {
                    ForEach(items) { item in
                        GearCard(
                            gear: item,
                            // Only for the kind that was asked for. A bike
                            // cannot be selected for a run, and offering it
                            // would be an offer the server refuses.
                            isSelected: selection?.currentID == item.id,
                            selectAction: canSelect(item) ? { choose(item) } : nil
                        ) {
                            editing = .edit(item)
                        }
                    }
                }

                if selection != nil, store.all(kind).contains(where: canSelect) {
                    Button("Use none for this session") {
                        selection?.choose(nil)
                        dismiss()
                    }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }

                Button {
                    editing = .create(kind)
                } label: {
                    Label("Add \(kind.singular)", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(!store.isConnected)
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 12)
            .padding(.bottom, RepbaseDesign.bottomBarClearance)
        }
        .repbaseScreen(.prepare)
        .navigationTitle("Gear")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Open on the kind that was asked for, once. Doing it on every
            // redraw would fight the user reaching for the other tab.
            if let selection, !didFocusKind {
                didFocusKind = true
                kind = selection.kind
            }
            await store.refresh()
        }
        .sheet(item: $editing) { mode in
            NavigationStack {
                GearEditorView(mode: mode)
            }
        }
    }

    /// Retired gear keeps its place in the list and its mileage, but cannot be
    /// put back into a session without being un-retired first.
    private func canSelect(_ item: Gear) -> Bool {
        guard let selection else { return false }
        return item.kind == selection.kind && !item.isRetired
    }

    private func choose(_ item: Gear) {
        selection?.choose(item.id)
        dismiss()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No \(kind.title.lowercased()) yet")
                .font(.subheadline.weight(.semibold))
            Text(
                kind == .shoe
                    ? "Add a pair and every run you tag with them adds to their mileage."
                    : "Add a bike and every ride you tag with it adds to its mileage."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

/// One shoe or bike: what it is, how far it has gone, and how much is left.
private struct GearCard: View {
    let gear: Gear
    /// Whether this is the one the session is using now.
    var isSelected: Bool = false
    /// Set only when the list was opened to choose. Nil means the card is
    /// being browsed, not picked from.
    var selectAction: (() -> Void)?
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            card
            if let selectAction {
                selectButton(action: selectAction)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(RepbasePalette.caramel, lineWidth: 2)
            }
        }
        .opacity(gear.isRetired ? 0.55 : 1)
    }

    /// Selecting and editing are different intentions, so they are different
    /// controls: the body opens the editor, the button picks it for today.
    private func selectButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(isSelected ? "Selected" : "Select")
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    isSelected
                        ? RepbasePalette.caramel.opacity(0.18)
                        : Color.primary.opacity(0.06),
                    in: Capsule()
                )
                .foregroundStyle(
                    isSelected ? RepbasePalette.caramel : Color.primary
                )
        }
        .buttonStyle(.plain)
        .disabled(isSelected)
    }

    private var card: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: gear.kind.symbolName)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(gear.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if gear.isDefault {
                        tag("DEFAULT")
                    }
                    if gear.isRetired {
                        tag("RETIRED")
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(
                        ImperialUnits.distanceText(
                            kilometers: gear.totalDistanceKilometers,
                            decimals: 1
                        )
                        .replacingOccurrences(of: " mi", with: "")
                    )
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("mi")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("^[\(gear.sessionCount) session](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                wearBar
            }
            // No padding, background or dimming here: the wrapper above owns
            // all of it, so the Select button sits inside the same card rather
            // than under a second one.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Only drawn when the user said where the end is.
    ///
    /// Without a stated life there is no fraction to fill, and inventing one —
    /// "shoes last 500 miles" — would turn a guess about somebody else's shoes
    /// into a warning about theirs.
    @ViewBuilder
    private var wearBar: some View {
        if let fraction = gear.wearFraction, let remaining = gear.remainingKilometers {
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.10))
                        Capsule()
                            .fill(barColor(fraction))
                            .frame(width: proxy.size.width * min(fraction, 1))
                    }
                }
                .frame(height: 6)

                Text(remainingText(remaining, fraction: fraction))
                    .font(.caption)
                    .foregroundStyle(fraction >= 1 ? barColor(fraction) : .secondary)
            }
        }
    }

    private func remainingText(_ remainingKilometers: Double, fraction: Double) -> String {
        let target = ImperialUnits.distanceText(
            kilometers: gear.retireAtKilometers ?? 0,
            decimals: 0
        )
        if remainingKilometers <= 0 {
            let over = ImperialUnits.distanceText(
                kilometers: -remainingKilometers,
                decimals: 0
            )
            return "\(over) past the \(target) you set"
        }
        let left = ImperialUnits.distanceText(kilometers: remainingKilometers, decimals: 0)
        return "\(left) left of \(target)"
    }

    private func barColor(_ fraction: Double) -> Color {
        // Three states, because "nearly done" is the one worth acting on and
        // it is invisible if the bar only turns red once it is too late.
        if fraction >= 1 { return .red }
        if fraction >= 0.85 { return .orange }
        return RepbasePalette.caramel
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }
}
