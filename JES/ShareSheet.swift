import SwiftUI

/// A SwiftUI wrapper around `UIActivityViewController` (the system share sheet).
/// This allows presenting the native iOS share dialog from SwiftUI by conforming to
/// `UIViewControllerRepresentable`, which bridges UIKit view controllers into SwiftUI.
///
/// Usage: present via `.sheet` and pass an array of items (URLs, strings, images, etc.)
/// that should be available as sharing options.
struct ShareSheet: UIViewControllerRepresentable {
    /// The items to share (e.g. file URLs, text strings, images).
    /// These are passed directly to `UIActivityViewController` as activity items.
    let items: [Any]

    /// Creates and returns the `UIActivityViewController` with the provided items.
    /// No custom activity types are registered — only the system-default activities
    /// (AirDrop, Files, Messages, etc.) are shown.
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items,
                                 applicationActivities: nil)
    }

    /// Called when SwiftUI state changes. No updates are needed here because the
    /// share sheet is a one-shot presentation — once displayed, its content is fixed.
    func updateUIViewController(_ uiViewController: UIActivityViewController,
                                context: Context) {
        // nothing to update
    }
}
