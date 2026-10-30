import AVFoundation
import SwiftUI
import UIKit

/// Rytivo's media-first entry, with real OS permission status rather than toggles
/// that pretend to grant camera/microphone access inside the app.
struct PostMediaEntryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var microphoneAccess = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var requestingMicrophone = false
    let isOpeningCamera: Bool
    let message: String?
    let onCamera: () -> Void
    let onLibrary: () -> Void
    let onContinue: () -> Void
    let onCancel: () -> Void

    private var theme: HomeTimeOfDay { .current }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Label("Cancel", systemImage: "xmark")
                        .font(.community(.subheadline, weight: .semibold))
                        .padding(.vertical, 12)
                }
                Spacer()
                Text("NEW POST").font(.community(.caption2, weight: .bold))
                    .tracking(1.5).foregroundStyle(theme.canvasSecondaryText)
            }
            .padding(.horizontal, RepbaseDesign.pageInset)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    actions
                    permissions
                    if let message {
                        Label(message, systemImage: "info.circle")
                            .font(.community(.caption)).foregroundStyle(theme.canvasSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(action: onContinue) {
                        HStack {
                            Text("Continue without media")
                            Spacer()
                            Image(systemName: "arrow.forward")
                        }
                        .font(.community(.subheadline, weight: .semibold))
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, RepbaseDesign.pageInset)
                .padding(.top, 32)
                .padding(.bottom, 28)
            }.scrollIndicators(.hidden)
        }
        .foregroundStyle(theme.canvasPrimaryText)
        .tint(theme.accent)
        .homeTimeScreen(theme)
        .onAppear(perform: refreshPermissions)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshPermissions() }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 72, height: 72)
                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
            Text("YOUR DAY, IN MOTION")
                .font(.community(.caption2, weight: .bold))
                .tracking(1.5).foregroundStyle(theme.accent)
            Text("Capture the work.\nShare the moment.")
                .font(.community(.largeTitle, weight: .bold)).tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text("Start with a photo or video. Add your caption, then connect it to your meal, workout, or day.")
                .font(.community(.subheadline)).foregroundStyle(theme.canvasSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: onCamera) {
                HStack {
                    Image(systemName: "camera")
                    Text(isOpeningCamera ? "Opening camera…" : "Open camera")
                    Spacer()
                    if isOpeningCamera { ProgressView().tint(theme.onPrimaryAction) }
                    else { Image(systemName: "arrow.up.right") }
                }
                .font(.community(.headline)).padding(18)
                .foregroundStyle(theme.onPrimaryAction)
                .background(theme.primaryActionSurface, in: RoundedRectangle(cornerRadius: 18))
            }.disabled(isOpeningCamera || !cameraAvailable)
            .opacity(cameraAvailable ? 1 : 0.5)
            Button(action: onLibrary) {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                    Text("Choose from camera roll")
                    Spacer()
                    Image(systemName: "chevron.forward")
                }
                .font(.community(.headline)).padding(18)
                .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.canvasBorder, lineWidth: 1))
            }.disabled(isOpeningCamera)
        }.buttonStyle(.plain)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CAPTURE ACCESS").font(.community(.caption2, weight: .bold))
                .tracking(1.2).foregroundStyle(theme.canvasSecondaryText)
            permissionRow("Camera", icon: "camera", status: cameraAccess)
            Divider()
            permissionRow("Microphone", icon: "mic", status: microphoneAccess)
            if cameraAvailable {
                if microphoneAccess == .notDetermined && cameraAccess == .authorized {
                    Button("Allow microphone for videos") {
                        guard !requestingMicrophone else { return }
                        requestingMicrophone = true
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .audio)
                            requestingMicrophone = false
                            refreshPermissions()
                        }
                    }.disabled(requestingMicrophone)
                    .font(.community(.subheadline, weight: .semibold))
                }
                Button(action: openSettings) {
                    Label("Camera & microphone settings", systemImage: "gearshape")
                        .font(.community(.subheadline, weight: .semibold))
                        .padding(.vertical, 10)
                }
                Text("Apple asks before capture. Photos work without microphone access. You can change access in Settings.")
                    .font(.community(.caption)).foregroundStyle(theme.canvasSecondaryText)
            } else {
                Text("Camera capture needs an iPhone. You can still choose photos and videos from the simulator’s library.")
                    .font(.community(.caption)).foregroundStyle(theme.canvasSecondaryText)
            }
        }
        .padding(18)
        .background(theme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.canvasBorder, lineWidth: 1))
    }

    private func permissionRow(_ title: LocalizedStringKey, icon: String, status: AVAuthorizationStatus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(theme.accent).frame(width: 22)
            Text(title).font(.community(.subheadline, weight: .semibold))
            Spacer()
            Text(permissionLabel(status)).font(.community(.caption, weight: .semibold))
                .foregroundStyle(theme.canvasSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func permissionLabel(_ status: AVAuthorizationStatus) -> LocalizedStringKey {
        guard cameraAvailable else { return "Simulator" }
        switch status {
        case .authorized: return "Allowed"
        case .denied: return "Off in Settings"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not requested"
        @unknown default: return "Unavailable"
        }
    }

    private func refreshPermissions() {
        cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
        microphoneAccess = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
