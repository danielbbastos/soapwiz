import SwiftUI
import UIKit

/// Thin SwiftUI wrapper around `UIActivityViewController` so a backup file can be
/// shared through the standard system share sheet (Save to Files, AirDrop, Mail…).
/// `onFinish` reports whether the user completed an activity.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onFinish: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish?(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
