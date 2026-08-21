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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                RepbaseScreenHeader(
                    eyebrow: isEditing ? "GEAR DETAILS" : "NEW GEAR",
                    title: screenTitle,
                    detail: introText
                )

                editorSection("IDENTITY") {
                    VStack(spacing: 0) {
                        editorialField(mode.kind == .shoe ? "SHOE NAME" : "BIKE NAME", text: $name, placeholder: namePlaceholder)
                        Divider().padding(.leading, 18)
                        editorialField("BRAND", text: $brand, placeholder: "Optional")
                    }
                }

                editorSection("MILEAGE & LIFECYCLE") {
                    VStack(spacing: 0) {
                        mileageRow(
                            title: "Already covered",
                            detail: mode.kind == .shoe
                                ? "Starting mileage before Repbase begins tracking."
                                : "Existing mileage before Repbase begins tracking rides.",
                            text: $startingMilesText,
                            placeholder: "0"
                        )
                        Divider().padding(.leading, 18)
                        mileageRow(
                            title: mode.kind == .shoe ? "Replace at" : "Service at",
                            detail: mode.kind == .shoe
                                ? "We will show remaining distance as sessions are saved."
                                : "Repbase will show the distance remaining until service.",
                            text: $retireAtMilesText,
                            placeholder: "None"
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("PREFERENCE")
                    Toggle(isOn: $isDefault) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.kind == .shoe ? "Use by default" : "Use for rides by default")
                                .font(.headline)
                            Text("Automatically select this \(mode.kind == .shoe ? "pair for runs" : "bike for cycling sessions").")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(RepbasePalette.caramel)
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("NOTES")
                    TextField(notesPlaceholder, text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(.vertical, 12)
                        .overlay(alignment: .top) { Divider() }
                }

                if case .edit(let gear) = mode {
                    Button(gear.isRetired ? "Put back into use" : "Retire gear") {
                        Task {
                            await store.setRetired(gear, retired: !gear.isRetired)
                            dismiss()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(gear.isRetired ? RepbasePalette.sage : Color.red)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.vertical, 18)
        }
        .repbaseScreen(.prepare)
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

    private var isEditing: Bool {
        if case .edit(_) = mode { return true }
        return false
    }

    private var screenTitle: String {
        if isEditing { return mode.kind == .shoe ? "Edit running shoes" : "Edit bike" }
        return mode.kind == .shoe ? "Add running shoes" : "Add a bike"
    }

    private var introText: String {
        mode.kind == .shoe
            ? "Give this pair a name, then decide how you want mileage tracked."
            : "Add the bike, then choose when Repbase should flag its next service."
    }

    private var notesPlaceholder: String {
        mode.kind == .shoe
            ? "Optional details about fit, color, or rotation"
            : "Optional details about setup, components, or service"
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(RepbasePalette.sage)
    }

    private func editorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(title)
            content()
                .background(RepbasePalette.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(RepbasePalette.sand.opacity(0.8), lineWidth: 1)
                }
        }
    }

    private func editorialField(
        _ label: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(RepbasePalette.caramel)
            TextField(placeholder, text: text)
                .font(.headline)
        }
        .padding(18)
    }

    private func mileageRow(
        title: String,
        detail: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                milesField(text, placeholder: placeholder)
                    .foregroundStyle(text.wrappedValue.isEmpty ? Color.secondary : RepbasePalette.caramel)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
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
