import SwiftUI

/// Reusable targets belong to the plan. These fields never log a performed set.
/// The unit is labelled, but choosing an exercise's display unit happens only
/// during training. Stable row IDs keep edits attached when sets are removed.
struct WorkoutPlannedSetTable: View {
    @Binding var exercise: Exercise
    let unit: WorkoutWeightUnit
    @Binding var weightInputs: [UUID: String]
    @Binding var repsInputs: [UUID: String]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?
    private let phase = WorkoutVisualPhase.prepare

    private enum Field: Hashable { case reps(UUID), weight(UUID) }
    private var rows: [WorkoutPlannedSet] { exercise.effectivePlannedSets }
    private var labels: [String] { WorkoutSetPolicy.labels(for: rows.map(\.setType)) }
    private var prefix: String { "workout.plan-set.\(exercise.id.uuidString)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PLANNED TARGETS")
                .font(.community(.caption2, weight: .bold))
                .foregroundStyle(phase.secondaryText)

            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 8) {
                    Text("Set").frame(width: 44)
                    Text("Reps").frame(maxWidth: .infinity)
                    Text("Weight (\(unit.label))").frame(maxWidth: .infinity)
                    Color.clear.frame(width: 44, height: 1).accessibilityHidden(true)
                }
                .font(.community(.caption2, weight: .bold))
                .foregroundStyle(phase.secondaryText)
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 6) {
                    if dynamicTypeSize.isAccessibilitySize {
                        HStack {
                            kindMenu(row, index: index)
                            Text("Set \(index + 1)").font(.community(.subheadline, weight: .semibold))
                            Spacer()
                            removeButton(row, index: index)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reps").font(.community(.caption))
                            repsField(row, index: index)
                            Text("Weight (\(unit.label))").font(.community(.caption))
                            weightField(row, index: index)
                        }
                    } else {
                        HStack(spacing: 8) {
                            kindMenu(row, index: index)
                            repsField(row, index: index)
                            weightField(row, index: index)
                            removeButton(row, index: index)
                        }
                    }
                    if !WorkoutPlannedSetPolicy.isValid([row]) {
                        Text("Use 1–1,000 reps and a valid weight, or leave targets blank.")
                            .font(.community(.caption))
                            .foregroundStyle(RepbaseDesign.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .contain)
            }

            Button {
                focusedField = nil
                var updated = rows
                updated.append(WorkoutPlannedSet())
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    exercise.replacePlannedSets(updated)
                }
            } label: {
                Label("Add set", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(PlannedSetOutlineButtonStyle())
            .disabled(rows.count >= WorkoutPlannedSetPolicy.maximumCount)
            .accessibilityIdentifier("\(prefix).add")

            Button {
                guard let first = rows.first, WorkoutPlannedSetPolicy.isValid([first]) else { return }
                focusedField = nil
                let updated = rows.map { row in
                    var row = row
                    row.targetReps = first.targetReps
                    row.targetWeightKilograms = first.targetWeightKilograms
                    weightInputs.removeValue(forKey: row.id)
                    repsInputs.removeValue(forKey: row.id)
                    return row
                }
                exercise.replacePlannedSets(updated)
            } label: {
                Text("Apply first set targets to all")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(PlannedSetOutlineButtonStyle())
            .disabled(rows.count < 2 || rows.first.map { !WorkoutPlannedSetPolicy.isValid([$0]) } == true)
            .accessibilityIdentifier("\(prefix).copy-first")
        }
        .onAppear { exercise.materializePlannedSets() }
        .toolbar {
            if focusedField != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    private func kindMenu(_ row: WorkoutPlannedSet, index: Int) -> some View {
        Menu {
            ForEach(WorkoutSetType.allCases) { kind in
                Button { update(row.id) { $0.setType = kind } } label: {
                    Label(kind.title, systemImage: kind == row.setType ? "checkmark" : kind.symbol)
                }
            }
        } label: {
            SetTypeBadge(type: row.setType, label: labels[index])
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Set \(index + 1): \(row.setType.title)")
        .accessibilityHint("Change set type")
        .accessibilityIdentifier("\(prefix).\(index + 1).type")
    }

    private func repsField(_ row: WorkoutPlannedSet, index: Int) -> some View {
        TextField("—", text: Binding(
            get: { repsInputs[row.id] ?? row.targetReps.map(String.init) ?? "" },
            set: { text in
                repsInputs[row.id] = text
                let normalized = NumberInput.latinDigits(text).trimmingCharacters(in: .whitespacesAndNewlines)
                // Keep invalid input invalid rather than quietly removing a
                // target. Zero is deliberately outside the planning range.
                let value = normalized.isEmpty ? nil
                    : normalized.allSatisfy(\.isNumber) ? (Int(normalized) ?? 0) : 0
                update(row.id) { $0.targetReps = value }
            }
        ))
        .keyboardType(.numberPad)
        .focused($focusedField, equals: .reps(row.id))
        .modifier(PlannedSetInputStyle(invalid: row.targetReps.map { !(1...1000).contains($0) } ?? false))
        .accessibilityLabel("Set \(index + 1) target reps")
        .accessibilityIdentifier("\(prefix).\(index + 1).reps")
    }

    private func weightField(_ row: WorkoutPlannedSet, index: Int) -> some View {
        TextField("—", text: Binding(
            get: { weightInputs[row.id] ?? row.targetWeightKilograms.map { unit.display(kilograms: $0) } ?? "" },
            set: { text in
                weightInputs[row.id] = text
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                update(row.id) { $0.targetWeightKilograms = trimmed.isEmpty ? nil : unit.kilograms(display: trimmed) }
            }
        ))
        .keyboardType(.decimalPad)
        .focused($focusedField, equals: .weight(row.id))
        .modifier(PlannedSetInputStyle(invalid: row.targetWeightKilograms.map { WorkoutPlannedSetPolicy.canonicalWeight($0) == nil } ?? false))
        .accessibilityLabel("Set \(index + 1) target weight in \(unit.title)")
        .accessibilityIdentifier("\(prefix).\(index + 1).weight")
    }

    private func removeButton(_ row: WorkoutPlannedSet, index: Int) -> some View {
        Button(role: .destructive) {
            focusedField = nil
            weightInputs.removeValue(forKey: row.id)
            repsInputs.removeValue(forKey: row.id)
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                exercise.replacePlannedSets(rows.filter { $0.id != row.id })
            }
        } label: {
            Image(systemName: "minus.circle").frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(phase.secondaryText)
        .disabled(rows.count <= 1)
        .accessibilityLabel("Remove set \(index + 1)")
        .accessibilityIdentifier("\(prefix).\(index + 1).remove")
    }

    private func update(_ id: UUID, _ change: (inout WorkoutPlannedSet) -> Void) {
        var updated = rows
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        change(&updated[index])
        exercise.replacePlannedSets(updated)
    }
}

private struct PlannedSetInputStyle: ViewModifier {
    let invalid: Bool
    private let phase = WorkoutVisualPhase.prepare
    func body(content: Content) -> some View {
        content
            .font(.community(.body, weight: .bold).monospacedDigit())
            .multilineTextAlignment(.center)
            .foregroundStyle(phase.primaryText)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(phase.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(invalid ? RepbaseDesign.danger : phase.cardBorder, lineWidth: 1)
            }
    }
}

private struct PlannedSetOutlineButtonStyle: ButtonStyle {
    private let phase = WorkoutVisualPhase.prepare
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.community(.subheadline, weight: .semibold))
            .foregroundStyle(phase.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(phase.accent.opacity(configuration.isPressed ? 0.12 : 0), in: Capsule())
            .overlay { Capsule().strokeBorder(phase.cardBorder, lineWidth: 1) }
    }
}
