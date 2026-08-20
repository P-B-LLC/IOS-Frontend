//
//  GearPickerRow.swift
//  IOS Frontend
//
//  Which shoe or bike a session is being done in.
//
//  It fills itself in with whatever was used last and then gets out of the
//  way. Being asked to choose before every run is a question with the same
//  answer almost every time, and a control that mostly repeats itself is a
//  control worth removing. Changing it is a trip to the gear list, which is
//  what the arrow is for.
//

import SwiftUI

struct GearPickerRow: View {
    /// Where the choice goes.
    enum Destination {
        /// Straight onto a session that already exists.
        case session(Int)
        /// Held until the session does. Before Start there is nothing to
        /// attach to, so the answer is kept and applied when it can be.
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

        NavigationLink {
            GearView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: kind.symbolName)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(
                        accent.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 8)
                    )

                if choices.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind == .shoe ? "Add your shoes" : "Add your bike")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(primaryText)
                        Text("Track how far each one has been.")
                            .font(.caption)
                            .foregroundStyle(secondaryText)
                    }
                    Spacer(minLength: 0)
                } else {
                    Text(kind == .shoe ? "Shoes" : "Bike")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryText)
                    Spacer(minLength: 6)
                    Text(selectedName(from: choices) ?? "Choose")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                accent.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task {
            // Fill in once, and only when nothing is chosen yet. Re-applying
            // would overwrite a deliberate choice every time the view came
            // back, which is the opposite of remembering it.
            guard !didApplyDefault else { return }
            didApplyDefault = true
            guard selectedID == nil,
                  let remembered = store.defaultGear(for: workoutType) else { return }
            select(remembered.id)
        }
    }

    private func selectedName(from choices: [Gear]) -> String? {
        guard let selectedID else { return nil }
        // Falls back to the full list so a retired item still names itself on
        // a session recorded before it was retired.
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
