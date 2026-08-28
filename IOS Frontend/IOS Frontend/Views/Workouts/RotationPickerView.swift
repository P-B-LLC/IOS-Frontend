//
//  RotationPickerView.swift
//  IOS Frontend
//
//  Choosing which rotation you are on, and when it takes over.
//
//  Switching is a handover rather than a cut: the rotation running now keeps
//  its days right up to the start date, so picking one for next Monday leaves
//  this week planned. The server decides what that means for the calendar; this
//  screen only asks the two questions.
//

import SwiftUI

struct RotationPickerView: View {
    @Environment(CycleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The rotation being switched to, held while its start date is chosen.
    @State private var choosing: WorkoutCycle?
    @State private var startOn = Calendar.current.startOfDay(for: Date())

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("You train one rotation at a time. Pick another and it takes over on the day you choose — everything up to then stays as planned.")
                        .font(.community(.footnote))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let active = store.activeCycle {
                        section("ON NOW", timeOfDay: timeOfDay) {
                            row(active, isActive: true, timeOfDay: timeOfDay)
                        }
                    }

                    if store.otherCycles.isEmpty {
                        Text("No other rotations yet. Build one and it will appear here to switch to.")
                            .font(.community(.subheadline))
                            .foregroundStyle(timeOfDay.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 10)
                    } else {
                        section("SWITCH TO", timeOfDay: timeOfDay) {
                            ForEach(store.otherCycles) { cycle in
                                row(cycle, isActive: false, timeOfDay: timeOfDay)
                            }
                        }
                    }

                    if let error = store.persistenceError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.community(.footnote))
                            .foregroundStyle(RepbaseDesign.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 16)
                .padding(.bottom, RepbaseDesign.bottomBarClearance)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Rotations")
            .navigationBarTitleDisplayMode(.inline)
            .homeTimeScreen(timeOfDay)
            .sheet(item: $choosing) { cycle in
                startSheet(cycle, timeOfDay: timeOfDay)
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        timeOfDay: HomeTimeOfDay,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.community(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(timeOfDay.accent)
            content()
        }
    }

    private func row(
        _ cycle: WorkoutCycle,
        isActive: Bool,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        Button {
            guard !isActive else { return }
            startOn = Calendar.current.startOfDay(for: Date())
            choosing = cycle
        } label: {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cycle.displayName)
                        .font(.community(.subheadline, weight: .semibold))
                        .foregroundStyle(timeOfDay.primaryText)
                        .lineLimit(1)
                    Text(summary(cycle))
                        .font(.community(.caption))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isActive {
                    Text("ON NOW")
                        .font(.community(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(timeOfDay.accent)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.community(.caption2))
                        .foregroundStyle(timeOfDay.secondaryText)
                }
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isActive || store.isSaving)
    }

    private func summary(_ cycle: WorkoutCycle) -> String {
        let days = cycle.length == 1 ? "1 day" : "\(cycle.length) days"
        let trained = cycle.orderedSlots.filter { !$0.isRest }.count
        return "\(days) · \(trained) training"
    }

    private func startSheet(
        _ cycle: WorkoutCycle,
        timeOfDay: HomeTimeOfDay
    ) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("When should \(cycle.displayName) start?")
                        .font(.community(size: 21, weight: .bold))
                        .foregroundStyle(timeOfDay.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(handoverExplanation)
                        .font(.community(.footnote))
                        .foregroundStyle(timeOfDay.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    DatePicker(
                        "Starts",
                        selection: $startOn,
                        in: Calendar.current.startOfDay(for: Date())...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)

                    Button {
                        let cycleToStart = cycle
                        let day = startOn
                        choosing = nil
                        Task {
                            await store.activate(cycleToStart, startOn: day)
                            if store.persistenceError == nil { dismiss() }
                        }
                    } label: {
                        Text("Switch to this rotation")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EditorialPrimaryButtonStyle())
                    .disabled(store.isSaving)
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Start date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { choosing = nil }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var handoverExplanation: String {
        guard let active = store.activeCycle else {
            return "It begins at day 1 on the date you pick."
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(startOn) {
            return "\(active.displayName) ends today and this one begins at day 1."
        }
        return "\(active.displayName) keeps running until then, and this one begins at day 1 on the day you pick."
    }
}
