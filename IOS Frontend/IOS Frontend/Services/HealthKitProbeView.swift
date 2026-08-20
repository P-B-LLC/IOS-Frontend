//
//  HealthKitProbeView.swift
//  IOS Frontend
//
//  A launch-time check that Apple Health actually answers.
//
//  Without a paid Apple Developer membership the HealthKit entitlement is
//  stripped from device builds and kept only for the simulator. Whether that
//  is enough is not something reading the build settings can settle: if the
//  entitlement is missing at runtime, `requestAuthorization` fails at once with
//  an error and no sheet, and that difference is visible from a script even
//  though the sheet itself needs a tap nobody can give it.
//

#if DEBUG
import HealthKit
import SwiftUI

struct HealthKitProbeView: View {
    @State private var lines: [String] = ["asking…"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines, id: \.self) { line in
                Text(line)
            }
        }
        .font(.footnote.monospaced())
        .padding(24)
        .task { await probe() }
    }

    private func probe() async {
        var found: [String] = []
        found.append("available: \(HKHealthStore.isHealthDataAvailable())")

        let store = HKHealthStore()
        guard let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            found.append("stepCount type: MISSING")
            lines = found
            return
        }

        found.append("status before: \(name(of: store.authorizationStatus(for: steps)))")

        // The call that tells us what we came to find out. A missing
        // entitlement throws here rather than showing anything.
        do {
            try await store.requestAuthorization(toShare: [], read: [steps])
            found.append("request: returned, no error")
        } catch {
            found.append("request FAILED: \(error.localizedDescription)")
        }

        found.append("status after: \(name(of: store.authorizationStatus(for: steps)))")

        // The question the card cannot answer: is Health empty, or is the
        // reading broken? "No steps" looks identical either way from the UI.
        let service = HealthKitService()
        let since = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let days = await service.dailySteps(since: since)
        found.append("days with steps in the last 7: \(days.count)")
        for day in days.prefix(7) {
            found.append("  \(day.day.formatted(.dateTime.month().day())): \(day.steps)")
        }

        // Raw sample count, so an empty statistics query can be told apart
        // from an empty Health database.
        let samples: Int = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: steps,
                predicate: HKQuery.predicateForSamples(withStart: since, end: Date()),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, result, error in
                continuation.resume(returning: error == nil ? (result?.count ?? 0) : -1)
            }
            store.execute(query)
        }
        found.append("raw step samples: \(samples) (-1 means the read failed)")

        lines = found
    }

    private func name(of status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .sharingDenied: "sharingDenied"
        case .sharingAuthorized: "sharingAuthorized"
        @unknown default: "unknown"
        }
    }
}
#endif
