import SwiftUI
import PencilKit

struct HandwritingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: HandwritingCanvas

        init(parent: HandwritingCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Push the current canvas drawing into the SwiftUI state
            parent.drawing = canvasView.drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen,
                                   color: UIColor.systemIndigo,
                                   width: 3.0)
        canvas.backgroundColor = .white
        canvas.isOpaque = true

        canvas.delegate = context.coordinator   // <- important
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.drawing = drawing
    }
}

@discardableResult
func saveHandwritingImage(_ image: UIImage) -> URL? {
    guard let pngData = image.pngData() else {
        print("Failed to create PNG data")
        return nil
    }

    guard let documentsDirectory = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first else {
        print("Could not find Documents directory")
        return nil
    }

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
