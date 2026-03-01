import SwiftUI
import PencilKit

/// A SwiftUI wrapper around PencilKit's `PKCanvasView`, used to capture the user's
/// handwritten answer to the selected exercise question.
///
/// The canvas is configured for Apple Pencil-only input (`pencilOnly` drawing policy)
/// so that finger gestures can still be used for scrolling the surrounding `ScrollView`
/// without accidentally drawing strokes.
///
/// A two-way `@Binding` keeps the SwiftUI `PKDrawing` state in sync with the underlying
/// UIKit canvas: the `Coordinator` pushes canvas changes *up* into SwiftUI, while
/// `updateUIView` pushes SwiftUI state *down* into the canvas (e.g. when the user taps
/// "Clear" and the drawing is reset to an empty `PKDrawing`).
/// 
struct HandwritingCanvas: UIViewRepresentable {
    /// The current drawing data, shared with the parent view via a binding.
    /// When the user draws new strokes, the coordinator updates this value.
    /// When the parent resets it (e.g. on "Clear"), `updateUIView` propagates the change.
    @Binding var drawing: PKDrawing

    /// The coordinator acts as the `PKCanvasViewDelegate`, forwarding drawing changes
    /// from the UIKit canvas back into SwiftUI's state management system.
    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: HandwritingCanvas

        init(parent: HandwritingCanvas) {
            self.parent = parent
        }

        /// Called by PencilKit whenever the user adds, removes, or modifies strokes.
        /// Syncs the updated drawing into the parent's `@Binding` so the rest of
        /// the SwiftUI view hierarchy can react (e.g. enabling the "Export" button).
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }

    /// Creates the coordinator that bridges PencilKit delegate callbacks to SwiftUI state.
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Creates and configures the PencilKit canvas view.
    /// - Drawing policy: `.pencilOnly` — only Apple Pencil creates strokes; finger input
    ///   is passed through for scrolling.
    /// - Tool: A pen with system indigo color and 3-point width, providing a clean look
    ///   suitable for Japanese character writing.
    /// - Background: opaque white, which ensures exported PNGs have a white background.
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .pencilOnly
        canvas.tool = PKInkingTool(.pen,
                                   color: UIColor.systemIndigo,
                                   width: 3.0)
        canvas.backgroundColor = .white
        canvas.isOpaque = true

        // Assign the coordinator as the canvas delegate so drawing changes
        // are forwarded back to SwiftUI.
        canvas.delegate = context.coordinator
        return canvas
    }

    /// Pushes SwiftUI state changes down into the UIKit canvas.
    /// This is called when the parent view resets `handwritingDrawing` (e.g. the "Clear"
    /// button sets it to an empty `PKDrawing()`), causing the canvas to clear on screen.
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.drawing = drawing
    }
}

/// A semi-transparent grid overlay that mimics traditional Japanese writing practice paper.
/// The grid helps with the alignment of characters while handwriting.
///
/// The grid is rendered as a `Path` inside a `GeometryReader` so it automatically scales
/// to fill whatever container it is placed in. It is meant to be overlaid on top of the
/// `HandwritingCanvas` with `.allowsHitTesting(false)` so it does not intercept touch events.
struct JapaneseWritingGrid: View {
    /// The size of each square cell in points. 75pt roughly matches a comfortable character
    /// size for handwriting on an iPad screen.
    let cellSize: CGFloat = 75

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { path in
                // Draw vertical grid lines spaced `cellSize` apart
                var x = cellSize
                while x < w {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                    x += cellSize
                }
                // Draw horizontal grid lines spaced `cellSize` apart
                var y = cellSize
                while y < h {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                    y += cellSize
                }
            }
            // Use a very light gray with low opacity so the grid is subtle and
            // doesn't distract from the user's handwriting.
            .stroke(Color.gray.opacity(0.12), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Renders the given `PKDrawing` image as a PNG and saves it to the app's Documents
/// directory as "handwriting.png". This file is later attached to the answer submission
/// sent to the server.
///
/// - Parameter image: The `UIImage` snapshot of the user's handwriting from the canvas.
/// - Returns: The file URL where the PNG was saved, or `nil` if the operation failed.
///
/// The `@discardableResult` attribute allows callers to ignore the return value when
/// they don't need the URL.
@discardableResult
func saveHandwritingImage(_ image: UIImage) -> URL? {
    // Convert the UIImage to PNG binary data
    guard let pngData = image.pngData() else {
        print("Failed to create PNG data")
        return nil
    }

    // Locate the app's Documents directory
    guard let documentsDirectory = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first else {
        print("Could not find Documents directory")
        return nil
    }

    // Write the PNG data to "handwriting.png", requesting to overwrite any previous export.
    let fileURL = documentsDirectory.appendingPathComponent("handwriting.png")

    do {
        try pngData.write(to: fileURL)
        print("Saved handwriting PNG at:", fileURL.path)
        return fileURL
    } catch {
        print("Error saving PNG:", error.localizedDescription)
        return nil
    }
}
