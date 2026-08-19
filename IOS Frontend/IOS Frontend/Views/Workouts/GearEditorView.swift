//
//  GearEditorView.swift
//  IOS Frontend
//
//  Adding a shoe or bike, and editing one.
//

import SwiftUI

struct GearEditorView: View {
    enum Mode: Identifiable, Hashable {
        case create(GearKind)
        case edit(Gear)

        var id: String {
            switch self {
            case .create(let kind): "create-\(kind.rawValue)"
            case .edit(let gear): "edit-\(gear.id)"
            }
        }

        var kind: GearKind {
            switch self {
            case .create(let kind): kind
            case .edit(let gear): gear.kind
            }
        }
    }

    let mode: Mode

    @Environment(GearStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brand = ""
    @State private var notes = ""
    /// Held as typed text, in miles, because a half-typed number is not a
    /// Double and clearing the field should not read as zero.
    @State private var startingMilesText = ""
    @State private var retireAtMilesText = ""
    @State private var isDefault = false
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                TextField(namePlaceholder, text: $name)
                TextField("Brand (optional)", text: $brand)
            } header: {
                Text(mode.kind == .shoe ? "Shoes" : "Bike")
            }

            Section {
                LabeledContent("Already covered") {
                    milesField($startingMilesText, placeholder: "0")
                }
            } footer: {
                Text(
                    "Miles it had on it before Repbase started counting. Leave at zero if it is new."
                )
            }

            Section {
                LabeledContent("Replace at") {
                    milesField($retireAtMilesText, placeholder: "None")
                }
            } footer: {
                Text(
                    mode.kind == .shoe
                        ? "Optional. Set a figure and Repbase shows how much is left; leave it empty and it just counts. How long a pair lasts depends on the shoe and the runner, so nothing is assumed."
                        : "Optional. Set a figure to be told when a service is due; leave it empty and it just counts."
                )
            }

            Section {
                Toggle("Use by default", isOn: $isDefault)
            } footer: {
                Text(
                    "Preselected when you start a \(mode.kind == .shoe ? "run" : "ride"). You can still change it for any single session."
                )
            }

            Section {
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(1...4)
            }

            if case .edit(let gear) = mode {
                Section {
                    Button(gear.isRetired ? "Put back into use" : "Retire") {
                        Task {
                            await store.setRetired(gear, retired: !gear.isRetired)
                            dismiss()
                        }
                    }
                } footer: {
                    Text(
                        "Retiring keeps every mile it has done and stops it being offered for new sessions."
                    )
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await save()
                        dismiss()
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || store.isSaving)
            }
        }
        .task {
            // Once: re-running this on every redraw would fight the keyboard.
            guard !didLoad else { return }
            didLoad = true
            if case .edit(let gear) = mode {
                name = gear.name
                brand = gear.brand
                notes = gear.notes
                startingMilesText = milesText(gear.initialDistanceKilometers)
                retireAtMilesText = gear.retireAtKilometers.map(milesText) ?? ""
                isDefault = gear.isDefault
            }
        }
    }

    private var title: String {
        switch mode {
        case .create(let kind): "New \(kind.singular)"
        case .edit: "Edit"
        }
    }

    private var namePlaceholder: String {
        mode.kind == .shoe ? "Pegasus 40" : "Domane AL 3"
    }

    private func milesField(
        _ text: Binding<String>,
        placeholder: String
    ) -> some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text("mi")
                .foregroundStyle(.secondary)
        }
    }

    private func milesText(_ kilometers: Double) -> String {
        guard kilometers > 0 else { return "" }
        return String(format: "%g", (ImperialUnits.miles(fromKilometers: kilometers) * 10).rounded() / 10)
    }

    /// Miles in the field, kilometres on the wire.
    private func kilometers(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let miles = Double(trimmed), miles >= 0 else {
            return nil
        }
        return miles * ImperialUnits.metersPerMile / 1000
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        switch mode {
        case .create(let kind):
            await store.create(
                GearDraft(
                    kind: kind,
                    name: trimmedName,
                    brand: brand.trimmingCharacters(in: .whitespaces),
                    notes: notes,
                    initialDistanceKilometers: kilometers(from: startingMilesText) ?? 0,
                    retireAtKilometers: kilometers(from: retireAtMilesText),
                    isDefault: isDefault
                )
            )
        case .edit(let gear):
            var updated = gear
            updated.name = trimmedName
            updated.brand = brand.trimmingCharacters(in: .whitespaces)
            updated.notes = notes
            updated.initialDistanceKilometers = kilometers(from: startingMilesText) ?? 0
            updated.retireAtKilometers = kilometers(from: retireAtMilesText)
            updated.isDefault = isDefault
            await store.update(updated)
        }
    }
}
