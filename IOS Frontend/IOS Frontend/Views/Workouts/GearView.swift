//
//  GearView.swift
//  IOS Frontend
//
//  Shoes and bikes, and how far each has been.
//

import SwiftUI

struct GearView: View {
    @Environment(GearStore.self) private var store

    @State private var kind: GearKind = .shoe
    @State private var editing: GearEditorView.Mode?

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
                        GearCard(gear: item) {
                            editing = .edit(item)
                        }
                    }
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
        .task { await store.refresh() }
        .sheet(item: $editing) { mode in
            NavigationStack {
                GearEditorView(mode: mode)
            }
        }
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
    let onTap: () -> Void

    var body: some View {
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .opacity(gear.isRetired ? 0.55 : 1)
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
