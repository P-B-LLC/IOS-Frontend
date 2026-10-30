//
//  ActivityLogFields.swift
//  IOS Frontend
//
//  The questions asked about an activity, chosen by the activity.
//

import SwiftUI
import UIKit

/// The fields for logging one activity: only what that activity asks about.
///
/// Time first, because it is the one thing every activity has and the only
/// one required. Then distance where the activity has one, the activity's own
/// questions, how hard it felt, and the extras last. Everything after the
/// time is optional and says so, so nobody stops at a question they cannot
/// answer.
struct ActivityLogFields: View {
    @Binding var draft: ActivityLogDraft
    /// What to ask. A session recorded live already has its time, and a
    /// measured distance must not be typed over.
    var asks: Set<Question> = Set(Question.allCases)
    var phase: WorkoutVisualPhase = .prepare
    /// When it can have finished: within the day it is logged on, and not
    /// later than now.
    var finishedRange: ClosedRange<Date> = Date.distantPast...Date().addingTimeInterval(60)

    enum Question: CaseIterable, Hashable {
        case finishedAt, duration, distance, details, effort, calories, notes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if asks.contains(.duration) { durationSection }
            if asks.contains(.finishedAt) { finishedAtSection }
            if asks.contains(.distance), draft.activity.distanceField != .none { distanceSection }
            if asks.contains(.details) {
                ForEach(draft.activity.detailFields) { field in detailSection(field) }
            }
            if asks.contains(.effort) { effortSection }
            if asks.contains(.calories) { caloriesSection }
            if asks.contains(.notes) { notesSection }
        }
    }

    // MARK: - Time

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow(Text("HOW LONG?"), optional: false)
            HStack(spacing: 10) {
                numberField("0", text: $draft.hours, width: 64, label: Text("h"), accessibility: Text("Hours"))
                numberField("0", text: $draft.minutes, width: 64, label: Text("min"), accessibility: Text("Minutes"))
                Spacer(minLength: 0)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                        chip(ActivityDurationText.text(seconds: Double(minutes * 60)),
                             selected: draft.durationSeconds == minutes * 60) {
                            draft.setDuration(minutes: minutes)
                        }
                    }
                }
            }
        }
    }

    private var finishedAtSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow(Text("FINISHED AT"), optional: false)
            DatePicker(
                "Finished at",
                selection: $draft.endedAt,
                in: finishedRange,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .environment(\.locale, .app)
        }
    }

    // MARK: - Distance

    private var distanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow(Text("DISTANCE"), optional: true)
            HStack(spacing: 10) {
                TextField("0.0", text: $draft.distance)
                    .keyboardType(.decimalPad)
                    .font(.community(.title3, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 14)
                    .frame(width: 120, height: 48)
                    .workoutOutline()
                    .accessibilityLabel("Distance")
                Picker("Distance unit", selection: $draft.distanceUnit) {
                    ForEach(ActivityLogDraft.DistanceUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                Spacer(minLength: 0)
            }
            if draft.distanceKilometers == .invalid {
                Text(ActivityLogDraft.Problem.invalidDistance.message)
                    .font(.community(.caption)).foregroundStyle(RepbaseDesign.danger)
            } else if let pace = draft.paceOrSpeedText {
                Text(pace)
                    .font(.community(.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(phase.accent)
            }
        }
    }

    // MARK: - The activity's own questions

    @ViewBuilder
    private func detailSection(_ field: ActivityDetailField) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow(Text(verbatim: field.title.uppercased(with: .app)), optional: true)
            switch field.kind {
            case .choice:
                FlowChips(options: field.options(for: draft.activity), selected: draft.details.text(field)) { value in
                    draft.details[field] = draft.details.text(field) == value ? nil : .text(value)
                } chip: { title, selected, action in
                    chip(title, selected: selected, action: action)
                }
            case .integer(let range):
                HStack(spacing: 10) {
                    numberField(
                        "—",
                        text: integerBinding(field, range: range),
                        width: 90,
                        label: field.unit.map { Text(verbatim: $0) },
                        accessibility: Text(verbatim: field.title)
                    )
                    if field == .poolLength {
                        ForEach([25, 33, 50], id: \.self) { length in
                            chip("\(length) \(ActivityDetailField.poolLength.unit ?? "m")", selected: draft.details.integer(.poolLength) == length) {
                                draft.details[.poolLength] = .integer(length)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            case .text(let maxLength):
                TextField("e.g. Thrusters, pull-ups, box jumps", text: textBinding(field, maxLength: maxLength), axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .workoutOutline()
                    .accessibilityLabel(field.title)
            }
        }
    }

    // MARK: - Effort and extras

    private var effortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow(Text("HOW HARD WAS IT?"), optional: true)
            EffortChart(value: $draft.perceivedEffort, phase: phase)
                .padding(14)
                .workoutOutline(radius: 18)
            Text("Your own rating of the whole session.")
                .font(.community(.caption)).foregroundStyle(phase.secondaryText)
        }
    }

    private var caloriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow(Text("CALORIES"), optional: true)
            HStack(spacing: 10) {
                TextField("—", text: Binding(
                    get: { draft.calories },
                    set: { draft.calories = String($0.filter(\.isNumber).prefix(5)) }
                ))
                .keyboardType(.numberPad)
                .font(.community(.title3, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 14)
                .frame(width: 120, height: 48)
                .workoutOutline()
                .accessibilityLabel("Calories, your estimate")
                Text("kcal").font(.community(.subheadline, weight: .semibold)).foregroundStyle(phase.secondaryText)
                Spacer(minLength: 0)
            }
            Text("Only if you know it, from a watch or machine. Saved as your estimate, not a measurement.")
                .font(.community(.caption)).foregroundStyle(phase.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !draft.calories.isEmpty, Int(draft.calories).map({ !ActivityLogDraft.caloriesRange.contains($0) }) ?? true {
                Text(ActivityLogDraft.Problem.invalidCalories.message)
                    .font(.community(.caption)).foregroundStyle(RepbaseDesign.danger)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow(Text("NOTES"), optional: true)
            TextField("How did it go?", text: Binding(
                get: { draft.notes },
                set: { draft.notes = String($0.prefix(ActivityLogDraft.maximumNotesLength)) }
            ), axis: .vertical)
            .lineLimit(3...8)
            .padding(12)
            .workoutOutline()
            .accessibilityLabel("Notes")
        }
    }

    // MARK: - Pieces

    private func eyebrow(_ title: Text, optional: Bool) -> some View {
        HStack(spacing: 6) {
            title
                .font(.community(.caption2, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(phase.secondaryText)
            if optional {
                Text("Optional")
                    .font(.community(size: 10, weight: .semibold))
                    .foregroundStyle(phase.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(phase.cardBorder.opacity(0.6), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func numberField(
        _ placeholder: LocalizedStringKey,
        text: Binding<String>,
        width: CGFloat,
        label: Text?,
        accessibility: Text
    ) -> some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: Binding(
                get: { text.wrappedValue },
                set: { text.wrappedValue = String($0.filter(\.isNumber).prefix(5)) }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.community(.title3, weight: .semibold).monospacedDigit())
            .frame(width: width, height: 48)
            .workoutOutline()
            .accessibilityLabel(accessibility)
            if let label {
                label.font(.community(.subheadline, weight: .semibold)).foregroundStyle(phase.secondaryText)
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.community(.caption, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? phase.onPrimaryAction : phase.primaryText)
                .background(selected ? phase.primaryActionSurface : phase.surfaceStart, in: Capsule())
                .overlay { Capsule().strokeBorder(phase.cardBorder, lineWidth: selected ? 0 : 1) }
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func integerBinding(_ field: ActivityDetailField, range: ClosedRange<Int>) -> Binding<String> {
        Binding(
            get: { draft.details.integer(field).map(String.init) ?? "" },
            set: { text in
                let digits = text.filter(\.isNumber)
                guard let value = Int(digits.prefix(5)) else { draft.details[field] = nil; return }
                draft.details[field] = .integer(min(value, range.upperBound))
            }
        )
    }

    private func textBinding(_ field: ActivityDetailField, maxLength: Int) -> Binding<String> {
        Binding(
            get: { draft.details.text(field) ?? "" },
            set: { text in
                let clipped = String(text.prefix(maxLength))
                draft.details[field] = clipped.isEmpty ? nil : .text(clipped)
            }
        )
    }
}

/// Chips that wrap onto as many lines as they need.
private struct FlowChips<Chip: View>: View {
    let options: [ActivityChoice]
    let selected: String?
    let onSelect: (String) -> Void
    @ViewBuilder let chip: (String, Bool, @escaping () -> Void) -> Chip

    var body: some View {
        WrappingLayout(spacing: 8) {
            ForEach(options) { option in
                chip(option.title, option.value == selected) { onSelect(option.value) }
            }
        }
    }
}

/// Lays children out left to right, starting a new line when one is full.
struct WrappingLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// Logging a planned activity after the fact: "Tennis" is on Tuesday, the
/// match is over, and nobody started a timer.
struct ActivityLogSheet: View {
    let workout: Workout
    let day: Weekday
    @Environment(WorkoutStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ActivityLogDraft
    @State private var problem: String?
    @State private var isSaving = false
    private let phase = WorkoutVisualPhase.prepare

    private let finishedRange: ClosedRange<Date>

    init(workout: Workout, day: Weekday, defaultEnd: Date, finishedRange: ClosedRange<Date>, distanceUnit: ActivityLogDraft.DistanceUnit) {
        self.workout = workout
        self.day = day
        self.finishedRange = finishedRange
        var draft = ActivityLogDraft(activity: workout.activity, endedAt: defaultEnd)
        draft.name = workout.name
        draft.distanceUnit = distanceUnit
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        Image(systemName: workout.activity.symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(phase.accent)
                            .frame(width: 44, height: 44)
                            .background(phase.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.name).font(.community(.headline))
                            Text(workout.activity.title).font(.community(.caption)).foregroundStyle(phase.secondaryText)
                        }
                    }
                    ActivityLogFields(draft: $draft, phase: phase, finishedRange: finishedRange)
                        .onChange(of: draft) { problem = nil }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    if let problem {
                        Text(problem).font(.community(.caption)).foregroundStyle(RepbaseDesign.danger)
                    }
                    Button(action: save) {
                        HStack {
                            if isSaving { ProgressView().tint(phase.onPrimaryAction) }
                            Text(isSaving ? "Saving activity…" : "Save to history")
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WorkoutPrimaryButtonStyle(phase: phase))
                    .disabled(isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(phase.canvasStart)
            }
            .navigationTitle("Log activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
            }
            .repbaseScreen(.prepare)
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        switch draft.validated() {
        case .failure(let failure):
            problem = failure.message
        case .success(let entry):
            isSaving = true
            Task {
                defer { isSaving = false }
                if let failure = await store.logActivity(entry, on: day, workoutServerID: workout.serverID) {
                    problem = failure
                } else {
                    RepbaseCelebrations.show(.workoutLogged)
                    dismiss()
                }
            }
        }
    }
}
