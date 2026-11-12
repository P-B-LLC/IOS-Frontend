//
//  WorkoutUnitControls.swift
//  IOS Frontend
//
//  The kg/lb switch and the rest-length menu, shared by every workout screen.
//

import SwiftUI

/// A two-position kg | lb switch.
///
/// Tapping changes the display only. The explicit default action lives in
/// `WorkoutWeightUnitControl`, not behind a hidden long-press menu.
struct WeightUnitToggle: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var selectionFeedback = 0
    var compact = false
    var onWillChange: () -> Void = {}

    private var preferences: WorkoutPreferences { store.preferences }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WorkoutWeightUnit.allCases) { unit in
                let selected = preferences.weightUnit == unit
                Button {
                    guard !selected else { return }
                    onWillChange()
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        preferences.useTemporarily(unit)
                    }
                    selectionFeedback += 1
                } label: {
                    Text(unit.label)
                        .font(.community(compact ? .caption : .subheadline, weight: .bold))
                        .foregroundStyle(selected ? WorkoutVisualPhase.focus.onPrimaryAction : WorkoutVisualPhase.focus.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 60, minHeight: 44)
                        .background {
                            if selected {
                                Capsule().fill(WorkoutVisualPhase.focus.primaryActionSurface)
                                    .padding(.vertical, 3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(unit.title)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("workout.weight-unit.\(unit.rawValue)")
            }
        }
        .padding(.horizontal, 3)
        .background(WorkoutVisualPhase.focus.accent.opacity(0.12), in: Capsule())
        .overlay {
            Capsule().strokeBorder(WorkoutVisualPhase.focus.cardBorder.opacity(contrast == .increased ? 1 : 0.65), lineWidth: 1)
        }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weight unit")
        .accessibilityHint("Changes how weights are shown. Your recorded weights do not change.")
    }
}

/// The labelled control sits immediately above the weights it changes.
/// Its optional second row makes remembering the choice an explicit action;
/// selecting kg/lb itself never writes the account or any recorded weight.
struct WorkoutWeightUnitControl: View {
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var onWillChange: () -> Void = {}
    var showsDefaultAction = true
    private let phase = WorkoutVisualPhase.focus

    private var preferences: WorkoutPreferences { store.preferences }
    private var isSavedDefault: Bool {
        preferences.hasLoadedUnit && !preferences.isSavingUnit
            && preferences.defaultWeightUnit == preferences.weightUnit
            && preferences.unitError == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Text("Weight unit")
                    .font(.community(.subheadline, weight: .semibold))
                    .foregroundStyle(phase.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                WeightUnitToggle(onWillChange: onWillChange)
            }
            if showsDefaultAction {
                defaultAction
                if let error = preferences.unitError {
                    Text(error)
                        .font(.community(.caption))
                        .foregroundStyle(RepbaseDesign.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("workout.weight-unit-error")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout.weight-unit-control")
    }

    private var defaultAction: some View {
        Button {
            onWillChange()
            let unit = preferences.weightUnit
            Task { await preferences.makeDefault(unit, using: store) }
        } label: {
            HStack(spacing: 8) {
                if preferences.isSavingUnit {
                    ProgressView().controlSize(.small)
                        .frame(width: 22, height: 22)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSavedDefault ? phase.primaryActionSurface : Color.clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(isSavedDefault ? phase.primaryActionSurface : phase.cardBorder, lineWidth: 1)
                        }
                        .overlay {
                            if isSavedDefault {
                                Image(systemName: "checkmark")
                                    .font(.community(.caption, weight: .bold))
                                    .foregroundStyle(phase.onPrimaryAction)
                            }
                        }
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                }
                Text(preferences.weightUnit == .metric ? "Use kg as my default" : "Use lb as my default")
                    .fixedSize(horizontal: false, vertical: true)
                if preferences.unitError != nil {
                    Spacer(minLength: 8)
                    Text("Retry").fontWeight(.bold)
                }
            }
            .font(.community(.caption, weight: .semibold))
            .foregroundStyle(isSavedDefault ? PlannerStyle.success : phase.accent)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(preferences.isSavingUnit || isSavedDefault || !store.isConnected)
        .accessibilityValue(preferences.isSavingUnit ? "Saving…" : isSavedDefault ? "Saved" : "")
        .accessibilityIdentifier("workout.weight-unit-default")
    }
}

/// Picks how long to rest after each set: the default, off, or a length.
struct RestDurationMenu<Label: View>: View {
    /// Nil means "use the default".
    let selection: Int?
    let defaultSeconds: Int
    var allowsDefault = true
    let onSelect: (Int?) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            if allowsDefault {
                Button {
                    onSelect(nil)
                } label: {
                    if selection == nil {
                        SwiftUI.Label("Default (\(RestDurationOptions.label(defaultSeconds)))", systemImage: "checkmark")
                    } else {
                        Text("Default (\(RestDurationOptions.label(defaultSeconds)))")
                    }
                }
                Divider()
            }
            ForEach(RestDurationOptions.seconds, id: \.self) { seconds in
                Button {
                    onSelect(seconds)
                } label: {
                    if selection == seconds {
                        SwiftUI.Label(RestDurationOptions.label(seconds), systemImage: "checkmark")
                    } else {
                        Text(RestDurationOptions.label(seconds))
                    }
                }
            }
        } label: {
            label()
        }
    }
}

/// "Rest 1:30" with a timer glyph, for a card or a row.
struct RestChip: View {
    let seconds: Int?
    let defaultSeconds: Int
    var phase: WorkoutVisualPhase = .focus

    private var effective: Int { seconds ?? defaultSeconds }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: effective > 0 ? "timer" : "timer.slash")
                .font(.community(.caption2, weight: .semibold))
            Text(effective > 0 ? "Rest \(RestDurationOptions.label(effective))" : "No rest timer")
                .font(.community(.caption, weight: .semibold))
                .monospacedDigit()
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(seconds == nil ? phase.secondaryText : phase.accent)
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
        .background(phase.accent.opacity(seconds == nil ? 0.06 : 0.12), in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(effective > 0 ? "Rest after each set, \(RestDurationOptions.label(effective))" : "No rest timer")
        .accessibilityHint("Changes how long to rest after each set")
    }
}

/// The colour that marks one superset, so the exercises in it read as a
/// group and two supersets in one workout are never confused.
enum SupersetPalette {
    static func color(for group: Int) -> Color {
        let colors: [Color] = [
            RepbasePalette.caramel,
            Color(hex: 0x4F7CAC),
            RepbasePalette.sage,
            Color(hex: 0x9A6FB0),
            Color(hex: 0xC4A23A)
        ]
        return colors[(max(group, 1) - 1) % colors.count]
    }
}

/// The badge in a set row's first column, coloured by what the set is for.
struct SetTypeBadge: View {
    let type: WorkoutSetType
    let label: String
    var isCurrent = false
    var isLogged = false

    static func tint(for type: WorkoutSetType) -> Color {
        switch type {
        case .normal: return Color.primary
        case .warmup: return Color(hex: 0xC4A23A)
        case .drop: return Color(hex: 0x4F7CAC)
        case .failure: return RepbaseDesign.danger
        }
    }

    var body: some View {
        Text(label)
            .font(.community(.subheadline, weight: .bold).monospacedDigit())
            .foregroundStyle(type == .normal ? (isLogged ? RepbaseDesign.success : Color.primary) : Self.tint(for: type))
            .frame(width: 34, height: 30)
            .background(
                (type == .normal ? Color.primary.opacity(isCurrent ? 0.08 : 0.04) : Self.tint(for: type).opacity(0.14)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}
