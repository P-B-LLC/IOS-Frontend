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
    @State private var service = HealthKitService()
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
