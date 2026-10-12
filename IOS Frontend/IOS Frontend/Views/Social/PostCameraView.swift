import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// System capture controls, including photo/video switching and camera reversal.
struct PostCameraView: UIViewControllerRepresentable {
    enum Result {
        case photo(UIImage)
        case video(PostVideoDraft)
        case library
        case cancelled
        case failure(String)
    }
    let allowsVideo: Bool
    let onResult: (Result) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        let available = UIImagePickerController.availableMediaTypes(for: .camera) ?? []
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier].filter {
            available.contains($0) && (allowsVideo || $0 != UTType.movie.identifier)
        }
        picker.videoMaximumDuration = 30
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        let library = UIButton(type: .system)
        library.setTitle("Camera roll", for: .normal)
        library.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
        library.tintColor = .white
        library.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        library.layer.cornerRadius = 16
        library.frame = CGRect(x: 20, y: 65, width: 150, height: 44)
        library.addAction(UIAction { _ in context.coordinator.finish(.library) }, for: .touchUpInside)
        // A full-screen interactive overlay would intercept the capture controls.
        picker.cameraOverlayView = library
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onResult: (Result) -> Void
        private var finished = false
        init(onResult: @escaping (Result) -> Void) { self.onResult = onResult }
        func finish(_ result: Result) {
            guard !finished else { return }
            finished = true
            onResult(result)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finish(.cancelled) }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                do { finish(.video(try PostVideoDraft.copyFrom(url))) }
                catch { finish(.failure(error.localizedDescription)) }
            } else if let image = info[.originalImage] as? UIImage {
                finish(.photo(image))
            } else {
                finish(.failure("That capture could not be read. Please try again."))
            }
        }
    }
}
