import SwiftUI
import UIKit

/// The system camera, for photographing something that is in front of the user
/// right now.
///
/// `PhotosPicker` covers everything already in the library; this covers the bar
/// that came out of the mold a minute ago, without a detour through the Camera
/// app and back.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    /// False on a device with no usable camera, where presenting the picker
    /// would only produce a black screen with a cancel button. Callers hide the
    /// option rather than offering a dead end.
    ///
    /// Not a simulator check: an iOS 26 simulator reports a camera and presents
    /// the real capture UI, whose viewfinder then never opens. Taking a photo
    /// can only be verified on a device.
    static var isSupported: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // `.editedImage` is absent unless editing is enabled, which it isn't:
            // cropping belongs to the user's own photo tools, not to a form row.
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}
