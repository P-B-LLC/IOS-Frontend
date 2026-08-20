//
//  GearPickerRow.swift
//  IOS Frontend
//
//  Choosing the shoe or bike a session is being done in.
//
//  Appears twice: while the session runs, so the choice is made before the
//  miles are, and again on the summary, so forgetting is not permanent. The
//  same row in both places, because they are the same decision.
//

import SwiftUI

struct GearPickerRow: View {
    /// Where the choice goes.
    enum Destination {
        /// Straight onto a session that already exists.
        case session(Int)
        /// Held until the session does. Before Start there is nothing to
        /// attach to, but that is exactly when a runner knows which shoes are
        /// on their feet, so the answer is kept and applied when it can be.
        case pending(Binding<Int?>)
    }

    let workoutType: WorkoutType
    let destination: Destination
    /// Colours differ between the planning page, the live session and the
    /// summary, so the caller supplies them rather than the row guessing.
    let primaryText: Color
    let secondaryText: Color
    let accent: Color

    @Environment(GearStore.self) private var store
    @State private var selectedID: Int?
    @State private var didApplyDefault = false

    var body: some View {
        if let kind = GearKind.forWorkoutType(workoutType) {
            content(kind: kind)
        }
    }

    @ViewBuilder
    private func content(kind: GearKind) -> some View {
        let choices = store.active(kind)

        HStack(spacing: 10) {
            Image(systemName: kind.symbolName)
                .font(.footnote.weight(.bold))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            if choices.isEmpty {
                // Nothing to pick from. Said plainly rather than shown as an
                // empty menu, which reads as broken.
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind == .shoe ? "No shoes added" : "No bikes added")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryText)
                    Text("Add a \(kind.singular) in Gear to track its mileage.")
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                }
                Spacer(minLength: 0)
            } else {
                Text(kind == .shoe ? "Shoes" : "Bike")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
                Spacer(minLength: 6)

                Menu {
                    ForEach(choices) { item in
                        Button {
                            select(item.id)
                        } label: {
                            if item.id == selectedID {
                                Label(item.displayName, systemImage: "checkmark")
                            } else {
                                Text(item.displayName)
                            }
                        }
                    }
                    Divider()
                    Button("None") { select(nil) }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedName(from: choices) ?? "Choose")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(accent)
                }
                .disabled(store.isSaving)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            accent.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .task {
            // Preselect the default once, and only when nothing is chosen yet.
            // Re-applying it would overwrite a deliberate choice every time the
            // view came back.
            guard !didApplyDefault else { return }
            didApplyDefault = true
            guard selectedID == nil,
                  let fallback = store.defaultGear(for: workoutType) else { return }
            select(fallback.id)
        }
    }

    private func selectedName(from choices: [Gear]) -> String? {
        guard let selectedID else { return nil }
        // Falls back to the full list so a retired item still names itself on
        // a session that was recorded before it was retired.
        return (choices.first { $0.id == selectedID }
            ?? store.gear(withID: selectedID))?.displayName
    }

    private func select(_ id: Int?) {
        selectedID = id
        switch destination {
        case .session(let sessionID):
            Task {
                await store.assign(id.flatMap(store.gear(withID:)), toSession: sessionID)
            }
        case .pending(let binding):
            binding.wrappedValue = id
        }
    }
}
