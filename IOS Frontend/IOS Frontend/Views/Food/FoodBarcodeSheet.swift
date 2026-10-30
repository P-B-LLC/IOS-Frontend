import AVFoundation
import SwiftUI
import Vision
import VisionKit

/// Frames stay on device. Only a validated product number goes to our API.
struct FoodBarcodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""
    @State private var cameraReady = false
    @State private var cameraUnavailable = false
    @State private var requestingCamera = false
    @State private var delivered = false
    let onCode: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Scan the barcode on the packet")
                        .font(.community(.title2, weight: .bold))
                    Text("Check your portion next. Nothing is added automatically.")
                        .foregroundStyle(.secondary)
                    if cameraReady {
                        FoodBarcodeCamera(onCode: finish, onUnavailable: {
                            cameraReady = false
                            cameraUnavailable = true
                        })
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    } else {
                        Button("Open camera") { Task { await openCamera() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(requestingCamera)
                    }
                    if cameraUnavailable {
                        Text("Camera unavailable. Enter the barcode below, or allow camera access in Settings.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Link("Open iOS settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                    TextField("Barcode number", text: $digits)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Barcode number")
                    Button("Find food") {
                        if let code = FoodBarcode.validated(digits) { finish(code) }
                    }
                    .buttonStyle(RepbasePrimaryButtonStyle())
                    .disabled(FoodBarcode.validated(digits) == nil || delivered)
                    Text("You can also type the number printed under the barcode.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onDisappear { cameraReady = false }
        }
    }

    @MainActor private func openCamera() async {
        requestingCamera = true
        defer { requestingCamera = false }
        guard DataScannerViewController.isSupported else { cameraUnavailable = true; return }
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        cameraReady = allowed && DataScannerViewController.isAvailable
        cameraUnavailable = !cameraReady
    }

    private func finish(_ code: String) {
        guard !delivered, let valid = FoodBarcode.validated(code) else { return }
        delivered = true
        cameraReady = false
        onCode(valid)
    }
}

private struct FoodBarcodeCamera: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onUnavailable: onUnavailable) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true,
            isGuidanceEnabled: true, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        // Start after SwiftUI has attached the controller to its hierarchy.
        DispatchQueue.main.async { [weak controller, weak coordinator = context.coordinator] in
            guard let controller, let coordinator, !coordinator.stopped else { return }
            do { try controller.startScanning() } catch { coordinator.onUnavailable() }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        coordinator.stopped = true
        uiViewController.stopScanning()
        uiViewController.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        let onUnavailable: () -> Void
        var stopped = false
        init(onCode: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
            self.onCode = onCode
            self.onUnavailable = onUnavailable
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !stopped else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let value = barcode.payloadStringValue else { continue }
                // UPC-E needs expansion, not an EAN-8 checksum interpretation.
                let code = barcode.observation.symbology == .upce ? FoodBarcode.expandUPCE(value) : FoodBarcode.validated(value)
                if let code {
                    stopped = true
                    dataScanner.stopScanning()
                    onCode(code)
                    return
                }
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            guard !stopped else { return }
            stopped = true
            dataScanner.stopScanning()
            onUnavailable()
        }
    }
}
