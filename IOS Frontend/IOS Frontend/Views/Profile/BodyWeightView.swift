//
//  BodyWeightView.swift
//  IOS Frontend
//
//  Weigh-ins, and which way they are going.
//
//  The profile has held a current weight and a target since the beginning,
//  with nothing in between: no way to record a reading, and so no way to see
//  whether the gap was closing. The endpoints were there the whole time and
//  nothing in the app had ever called them.
//

import Charts
import SwiftUI

struct BodyWeightView: View {
    @Environment(ActivityStore.self) private var store

    @State private var isAdding = false
    @State private var entry = ""
    @State private var recordedAt = Date()
    @State private var saveError: String?

    private var readings: [BodyWeightReading] { store.bodyWeights }

    var body: some View {
        let timeOfDay = HomeTimeOfDay.current

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(timeOfDay: timeOfDay)

                if let message = store.bodyWeightError {
                    notice(message, timeOfDay: timeOfDay)
                }

                if readings.isEmpty {
                    empty(timeOfDay: timeOfDay)
                } else {
                    summary(timeOfDay: timeOfDay)
                    if readings.count > 1 {
                        chart(timeOfDay: timeOfDay)
                    } else {
                        notice(
                            "One reading so far. A second gives this a direction.",
                            timeOfDay: timeOfDay
                        )
                    }
                    history(timeOfDay: timeOfDay)
                }
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Body weight")
        .navigationBarTitleDisplayMode(.inline)
        // Pushed from the profile, so the back chevron is already the way out
        // and a Close button beside it would be a second one.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a weigh-in")
            }
        }
        .homeTimeScreen(timeOfDay)
        .sheet(isPresented: $isAdding) { addSheet(timeOfDay: timeOfDay) }
        .task { await store.loadBodyWeights() }
    }

    private func header(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BODY WEIGHT")
                .font(.community(size: 10, weight: .bold))
                .tracking(1.25)
                .foregroundStyle(timeOfDay.accent)
            Text("Which way is it going?")
                .font(.community(size: 32, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text("One weigh-in says almost nothing. The line between them is the part worth reading.")
                .font(.community(.subheadline))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
        }
    }

    private func summary(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LATEST")
                    .font(.community(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(timeOfDay.canvasSecondaryText)
                Text(store.latestBodyWeight.map { format($0.kilograms) } ?? "—")
                    .font(.community(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
            }
            if let trend = store.bodyWeightTrend {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TREND")
                        .font(.community(size: 9, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                    Label(
                        "\(trend >= 0 ? "+" : "")\(format(trend))",
                        systemImage: trend >= 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.community(.title3, weight: .bold))
                    .foregroundStyle(timeOfDay.canvasPrimaryText)
                    // Deliberately not coloured good or bad. Up is what some
                    // people are training for and what others are avoiding,
                    // and the app has not been told which.
                    Text("recent three vs first three")
                        .font(.community(.caption2))
                        .foregroundStyle(timeOfDay.canvasSecondaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func chart(timeOfDay: HomeTimeOfDay) -> some View {
        Chart(readings) { reading in
            AreaMark(
                x: .value("Date", reading.recordedAt),
                y: .value("Weight", reading.kilograms)
            )
            .foregroundStyle(timeOfDay.accent.opacity(0.14))
            LineMark(
                x: .value("Date", reading.recordedAt),
                y: .value("Weight", reading.kilograms)
            )
            .foregroundStyle(timeOfDay.accent)
            .interpolationMethod(.monotone)
            PointMark(
                x: .value("Date", reading.recordedAt),
                y: .value("Weight", reading.kilograms)
            )
            .foregroundStyle(timeOfDay.accent)
        }
        // Never from zero. A scale starting at zero turns a real four-kilo
        // change into a flat line, which is the one thing this page exists to
        // show.
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 230)
        .accessibilityLabel("Body weight over time")
    }

    private func history(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EVERY READING")
                .font(.community(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(timeOfDay.canvasSecondaryText)
            ForEach(readings.reversed()) { reading in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(format(reading.kilograms))
                            .font(.community(.headline))
                            .foregroundStyle(timeOfDay.canvasPrimaryText)
                        Text(reading.recordedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                            .font(.community(.caption))
                            .foregroundStyle(timeOfDay.canvasSecondaryText)
                        if !reading.notes.isEmpty {
                            Text(reading.notes)
                                .font(.community(.caption))
                                .foregroundStyle(timeOfDay.canvasSecondaryText)
                        }
                    }
                    Spacer()
                    // First tap, as everywhere else in this app. A weigh-in
                    // is a number you can type again, not work you lose.
                    Button {
                        Task { await store.deleteBodyWeight(reading) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.community(.footnote, weight: .semibold))
                            .foregroundStyle(RepbaseDesign.warning)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete the reading from \(reading.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Divider().opacity(0.4) }
            }
        }
    }

    private func addSheet(timeOfDay: HomeTimeOfDay) -> some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack {
                        TextField("0.0", text: $entry)
                            .keyboardType(.decimalPad)
                            .font(.community(.title2, weight: .semibold))
                        Text("kg").foregroundStyle(.secondary)
                    }
                    DatePicker("Recorded", selection: $recordedAt, in: ...Date())
                }
                if let saveError {
                    Section { Text(saveError).foregroundStyle(RepbaseDesign.warning) }
                }
            }
            .navigationTitle("Add a weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isAdding = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(parsed == nil || store.isSavingBodyWeight)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// A believable human weight in kilograms.
    ///
    /// The bound is not fussiness: the field takes a decimal pad, and the
    /// difference between 82 and 820 is one slip that would flatten the chart
    /// for every reading after it.
    private var parsed: Double? {
        guard let value = Double(entry.trimmingCharacters(in: .whitespaces)),
              value > 20, value < 500 else { return nil }
        return value
    }

    private func save() {
        guard let kilograms = parsed else { return }
        saveError = nil
        Task {
            if let problem = await store.recordBodyWeight(kilograms: kilograms, at: recordedAt) {
                saveError = problem
            } else {
                entry = ""
                recordedAt = Date()
                isAdding = false
            }
        }
    }

    private func format(_ kilograms: Double) -> String {
        String(format: "%.1f kg", kilograms)
    }

    private func notice(_ message: String, timeOfDay: HomeTimeOfDay) -> some View {
        Text(message)
            .font(.community(.footnote))
            .foregroundStyle(timeOfDay.canvasSecondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .repbaseCard(contentPadding: 0, cornerRadius: 14)
    }

    private func empty(timeOfDay: HomeTimeOfDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No weigh-ins yet")
                .font(.community(.headline))
                .foregroundStyle(timeOfDay.canvasPrimaryText)
            Text("Add one with the plus button. Two readings are enough to draw a line; a fortnight of them is enough to trust it.")
                .font(.community(.subheadline))
                .foregroundStyle(timeOfDay.canvasSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .repbaseCard(contentPadding: 0, cornerRadius: 16)
    }
}
