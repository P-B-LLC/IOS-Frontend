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
            // Opened to choose, not just to browse: the list shows a Select
            // on each item of this kind and comes straight back with it.
            GearView(
                selection: GearView.Selection(
                    kind: kind,
                    currentID: selectedID,
                    choose: { select($0) }
                )
            )
        } label: {
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    gearIcon(for: kind)
                        .frame(width: 34, height: 34)
                    Text("GEAR")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(accent)
                }
                .frame(width: 64)

                Rectangle()
                    .fill(accent.opacity(0.24))
                    .frame(width: 1, height: 54)
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 5) {
                    Text(kind == .shoe ? "Shoes" : "Bike")
                        .font(.headline)
                        .foregroundStyle(primaryText)
                    Text(selectionDetail(for: kind, choices: choices))
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Text(selectionAction(for: choices))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(accent)

                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 82)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RepbasePalette.paper.opacity(0.92),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(accent.opacity(0.24), lineWidth: 1)
            }
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

    @ViewBuilder
    private func gearIcon(for kind: GearKind) -> some View {
        if kind == .shoe {
            Image("RepbaseSpeedSole")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(RepbaseDesign.success)
        } else {
            Image(systemName: kind.symbolName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(accent)
        }
    }

    private func selectionDetail(for kind: GearKind, choices: [Gear]) -> String {
        if choices.isEmpty {
            return kind == .shoe
                ? "Add shoes to track their distance"
                : "Add a bike to track its distance"
        }
        if let selected = selectedName(from: choices) { return selected }
        return kind == .shoe ? "Select gear for this run" : "Select gear for this ride"
    }

    private func selectionAction(for choices: [Gear]) -> String {
        if choices.isEmpty { return "Add" }
        return selectedName(from: choices) == nil ? "Choose" : "Change"
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
