//
//  SessionExerciseCard.swift
//  IOS Frontend
//
//  One exercise of a lifting session: its sets as a table, and its settings.
//

import SwiftUI
import UIKit

/// Which field of which set has the keyboard, so Next can move along a row
/// and on to the next set without reaching for the screen.
enum SessionField: Hashable {
    case weight(UUID)
    case reps(UUID)
}

struct SessionExerciseCard: View {
    let day: Weekday
    let exercise: SessionExerciseDraft
    let position: Int
    let count: Int
    let isFocused: Bool
    /// The session's other exercises, for "Superset with…".
    let others: [SessionExerciseDraft]
    var focusedField: FocusState<SessionField?>.Binding
    @Binding var weightInputs: [UUID: String]
    let onReorder: () -> Void
    let onRemove: () -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var expandedWhileComplete = false
    @State private var confirmingSetDeletion: WorkoutSetDraft?
    @State private var confirmingRemoval = false
    private let phase = WorkoutVisualPhase.focus

    private var unit: WorkoutWeightUnit { store.preferences.weightUnit }
    private var labels: [String] { WorkoutSetPolicy.labels(for: exercise.sets.map(\.setType)) }
    private var currentSetID: UUID? { isFocused ? exercise.currentSet?.id : nil }
    private var isCollapsed: Bool { exercise.isComplete && !isFocused && !expandedWhileComplete }
    private var supersetColor: Color? { exercise.supersetGroup.map { SupersetPalette.color(for: $0) } }

    var body: some View {
        HStack(spacing: 0) {
            if let supersetColor {
                Capsule().fill(supersetColor).frame(width: 4).padding(.vertical, 12)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 12) {
                header
                if isCollapsed {
                    collapsedSummary
                } else {
                    settingsRow
                    setTable
                    Button {
                        store.addSessionSet(on: day, exerciseID: exercise.id)
                    } label: {
                        Label("Add set", systemImage: "plus")
                            .font(.community(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(phase.primaryText)
                    .background(phase.cardBorder.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(minHeight: 44)
                    .disabled(store.isSaving)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(phase.surfaceStart, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isFocused ? phase.accent.opacity(0.55) : phase.cardBorder, lineWidth: isFocused ? 1.5 : 1)
        }
        .shadow(color: phase.shadow.opacity(isFocused ? 0.45 : 0.2), radius: isFocused ? 8 : 3, x: 0, y: 2)
        .animation(.snappy(duration: 0.22), value: isCollapsed)
        .confirmationDialog(
            "Delete this logged set?",
            isPresented: Binding(get: { confirmingSetDeletion != nil }, set: { if !$0 { confirmingSetDeletion = nil } }),
            titleVisibility: .visible,
            presenting: confirmingSetDeletion
        ) { set in
            Button("Delete set", role: .destructive) {
                store.removeSessionSet(on: day, exerciseID: exercise.id, setID: set.id)
            }
            Button("Keep set", role: .cancel) {}
        } message: { _ in
            Text("Its weight and reps are removed from this workout's record.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.focusSessionExercise(exercise.id)
                if exercise.isComplete { expandedWhileComplete.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(position) of \(count)")
                            .font(.community(.caption2, weight: .bold))
                            .foregroundStyle(isFocused ? phase.accent : phase.secondaryText)
                            .monospacedDigit()
                        if let supersetColor {
                            Text("SUPERSET")
                                .font(.community(size: 9, weight: .heavy))
                                .tracking(0.6)
                                .foregroundStyle(supersetColor)
                        }
                        if exercise.isComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.community(.caption2))
                                .foregroundStyle(RepbaseDesign.success)
                        }
                    }
                    Text(exercise.displayName)
                        .font(.community(.headline))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(exercise.displayName), exercise \(position) of \(count)")
            .accessibilityHint(isFocused ? "Current exercise" : "Makes this the current exercise")

            menu
        }
    }

    private var menu: some View {
        Menu {
            Button { onReorder() } label: { Label("Reorder exercises", systemImage: "arrow.up.arrow.down") }
            if exercise.supersetGroup != nil {
                Button { store.removeFromSuperset(on: day, exerciseID: exercise.id) } label: {
                    Label("Remove from superset", systemImage: "link.badge.plus")
                }
            }
            if !others.isEmpty {
                Menu {
                    ForEach(others) { other in
                        Button(other.name) { store.supersetSessionExercise(on: day, exerciseID: exercise.id, with: other.id) }
                    }
                } label: { Label("Superset with…", systemImage: "link") }
            }
            Divider()
            Button(role: .destructive) {
                // Asked only when something recorded would go with it.
                if exercise.loggedCount > 0 { confirmingRemoval = true } else { onRemove() }
            } label: { Label("Remove exercise", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.community(.subheadline, weight: .bold))
                .foregroundStyle(phase.secondaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Options for \(exercise.displayName)")
        .confirmationDialog("Remove this exercise?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove \(exercise.displayName)", role: .destructive, action: onRemove)
            Button("Keep exercise", role: .cancel) {}
        } message: {
            Text("\(exercise.loggedCount) logged sets will be removed from this workout. Your other exercises and your rest timer are not affected.")
        }
    }

    private var collapsedSummary: some View {
        HStack {
            Text("\(exercise.loggedCount) of \(exercise.sets.count) sets logged")
                .font(.community(.caption, weight: .semibold))
                .foregroundStyle(RepbaseDesign.success)
            Spacer()
            Text("Show sets").font(.community(.caption, weight: .semibold)).foregroundStyle(phase.accent)
        }
        .contentShape(Rectangle())
        .onTapGesture { expandedWhileComplete = true }
    }

    // MARK: - Settings

    private var settingsRow: some View {
        HStack(spacing: 8) {
            RestDurationMenu(
                selection: exercise.restSeconds,
                defaultSeconds: store.preferences.defaultRestSeconds
            ) { seconds in
                store.setSessionRest(on: day, exerciseID: exercise.id, seconds: seconds)
            } label: {
                RestChip(seconds: exercise.restSeconds, defaultSeconds: store.preferences.defaultRestSeconds)
            }
            if let reps = exercise.targetReps {
                Text("Target \(reps) reps")
                    .font(.community(.caption, weight: .semibold))
                    .foregroundStyle(phase.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Sets

    private var setTable: some View {
        VStack(spacing: 4) {
            if !dynamicTypeSize.isAccessibilitySize { columnHeaders }
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                SessionSetRow(
                    day: day,
                    exercise: exercise,
                    set: set,
                    index: index,
                    label: labels[index],
                    isCurrent: set.id == currentSetID,
                    focusedField: focusedField,
                    weightInputs: $weightInputs,
                    onDelete: {
                        if set.isLogged { confirmingSetDeletion = set }
                        else { store.removeSessionSet(on: day, exerciseID: exercise.id, setID: set.id) }
                    }
                )
            }
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Text("SET").frame(width: 34)
            Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
            Text(unit.label.uppercased()).frame(width: 70)
            Text("REPS").frame(width: 54)
            Image(systemName: "checkmark").frame(width: 44)
        }
        .font(.community(size: 10, weight: .bold))
        .tracking(0.4)
        .foregroundStyle(phase.secondaryText)
        .accessibilityHidden(true)
    }
}

/// One set: its kind, last time's numbers, today's weight and reps, and the
/// check that logs it.
private struct SessionSetRow: View {
    let day: Weekday
    let exercise: SessionExerciseDraft
    let set: WorkoutSetDraft
    let index: Int
    let label: String
    let isCurrent: Bool
    var focusedField: FocusState<SessionField?>.Binding
    @Binding var weightInputs: [UUID: String]
    let onDelete: () -> Void

    @Environment(WorkoutStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let phase = WorkoutVisualPhase.focus

    private var unit: WorkoutWeightUnit { store.preferences.weightUnit }
    private var hint: PreviousSet? { store.previousSet(for: exercise, at: index) }
    private var isPending: Bool { store.isSetPending(set.id) }
    private var canComplete: Bool { store.canComplete(set, in: exercise) }

    private var weightPlaceholder: String {
        if let target = exercise.targetWeightKilograms(for: set) { return unit.display(kilograms: target) }
        if let weight = hint?.weightKilograms { return unit.display(kilograms: weight) }
        return "—"
    }

    private var repsPlaceholder: String {
        if let reps = exercise.targetReps(for: set) { return "\(reps)" }
        if let reps = hint?.reps { return "\(reps)" }
        return "—"
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            typeMenu
            previousButton
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 8) { weightField; repsField; checkButton }
            } else {
                weightField
                repsField
                checkButton
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(set.isLogged ? RepbaseDesign.success.opacity(0.12) : isCurrent ? phase.accent.opacity(0.07) : Color.clear)
        }
        .overlay(alignment: .leading) {
            if isCurrent && !set.isLogged {
                Capsule().fill(phase.accent).frame(width: 3).padding(.vertical, 6).offset(x: -6)
            }
        }
        .animation(.snappy(duration: 0.2), value: set.isLogged)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowLabel)
    }

    private var rowLabel: String {
        switch set.setType {
        case .normal:
            return String(localized: "Set \(index + 1)", bundle: .app, locale: .app)
        default:
            return String(localized: "Set \(index + 1), \(set.setType.title)", bundle: .app, locale: .app, comment: "A set's place, then its kind")
        }
    }

    private var typeMenu: some View {
        Menu {
            ForEach(WorkoutSetType.allCases) { type in
                Button {
                    store.setSessionSetType(type, on: day, exerciseID: exercise.id, setID: set.id)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(type.title)
                            Text(type.explanation)
                        }
                    } icon: {
                        Image(systemName: set.setType == type ? "checkmark" : type.symbol)
                    }
                }
            }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete set", systemImage: "trash") }
                .disabled(exercise.sets.count < 2)
        } label: {
            SetTypeBadge(type: set.setType, label: label, isCurrent: isCurrent, isLogged: set.isLogged)
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(isPending)
        .accessibilityLabel("Set kind: \(set.setType.title)")
        .accessibilityHint("Changes what this set is for, or deletes it")
    }

    private var previousButton: some View {
        Button {
            guard let hint, !set.isLogged else { return }
            if let weight = hint.weightKilograms {
                weightInputs.removeValue(forKey: set.id)
                store.updateSessionSet(on: day, exerciseID: exercise.id, setID: set.id, weightKilograms: "\(weight)")
            }
            if let reps = hint.reps {
                store.updateSessionSet(on: day, exerciseID: exercise.id, setID: set.id, reps: "\(reps)")
            }
        } label: {
            Text(hint?.summary(in: unit) ?? "—")
                .font(.community(.caption, weight: .medium).monospacedDigit())
                .foregroundStyle(phase.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(hint == nil || set.isLogged || isPending)
        .accessibilityLabel(hint?.summary(in: unit).map { "Last time \($0)" } ?? "No previous set")
        .accessibilityHint(hint == nil ? "" : "Copies last time's weight and reps into this set")
    }

    private var weightField: some View {
        TextField(weightPlaceholder, text: Binding(
            get: { weightInputs[set.id] ?? unit.display(kilograms: set.weightKilograms) },
            set: { value in
                weightInputs[set.id] = value
                store.updateSessionSet(on: day, exerciseID: exercise.id, setID: set.id, weightKilograms: unit.kilograms(display: value))
            }
        ))
        .keyboardType(.decimalPad)
        .focused(focusedField, equals: .weight(set.id))
        .modifier(SetFieldStyle(width: 70, invalid: !set.isWeightValid, logged: set.isLogged))
        .disabled(set.isLogged || isPending)
        .accessibilityLabel("Weight in \(unit.title)")
    }

    private var repsField: some View {
        TextField(repsPlaceholder, text: Binding(
            get: { set.reps },
            set: { store.updateSessionSet(on: day, exerciseID: exercise.id, setID: set.id, reps: $0) }
        ))
        .keyboardType(.numberPad)
        .focused(focusedField, equals: .reps(set.id))
        .modifier(SetFieldStyle(width: 54, invalid: !set.reps.isEmpty && !set.areRepsValid, logged: set.isLogged))
        .disabled(set.isLogged || isPending)
        .accessibilityLabel("Reps")
    }

    private var checkButton: some View {
        Button {
            focusedField.wrappedValue = nil
            if set.isLogged {
                store.toggleSessionSetLogged(on: day, exerciseID: exercise.id, setID: set.id)
            } else {
                weightInputs.removeValue(forKey: set.id)
                store.completeSessionSet(on: day, exerciseID: exercise.id, setID: set.id)
            }
        } label: {
            ZStack {
                if isPending {
                    ProgressView().controlSize(.small)
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(set.isLogged ? RepbaseDesign.success : Color.clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(set.isLogged ? Color.clear : (canComplete ? phase.primaryText.opacity(0.55) : phase.cardBorder), lineWidth: 1.5)
                        }
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark")
                        .font(.community(.subheadline, weight: .bold))
                        .foregroundStyle(set.isLogged ? Color.white : (canComplete ? phase.primaryText : phase.secondaryText.opacity(0.5)))
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPending || store.isSaving || (!set.isLogged && !canComplete))
        .sensoryFeedback(.success, trigger: set.isLogged) { _, logged in logged }
        .accessibilityLabel(set.isLogged ? "Logged. Double-tap to unlog." : "Log set")
        .accessibilityHint(set.isLogged ? "" : (canComplete ? "Logs this set and starts your rest" : "Enter reps to log this set"))
    }
}

private struct SetFieldStyle: ViewModifier {
    let width: CGFloat
    let invalid: Bool
    let logged: Bool

    func body(content: Content) -> some View {
        content
            .font(.community(.subheadline, weight: .bold).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: width, height: 36)
            .background(
                logged ? Color.clear : WorkoutVisualPhase.focus.cardBorder.opacity(0.45),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                if invalid {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(RepbaseDesign.danger, lineWidth: 1)
                }
            }
            .frame(minHeight: 44)
    }
}
