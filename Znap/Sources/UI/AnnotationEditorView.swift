import SwiftUI

/// The root SwiftUI view for the annotation editor.
///
/// Combines ``AnnotationToolbar`` (top) with a scrollable ``AnnotationCanvasView``
/// (below). Manages undo/redo state, save, and copy-to-clipboard.
struct AnnotationEditorView: View {

    // MARK: - State

    @State private var document: AnnotationDocument
    @State private var selectedTool: AnnotationDocument.AnnotationType = .arrow
    @State private var selectedColor: AnnotationDocument.CodableColor = .defaultRed
    @State private var strokeWidth: CGFloat = 3
    @State private var undoStack: [[AnnotationDocument.Annotation]] = []
    @State private var redoStack: [[AnnotationDocument.Annotation]] = []
    @State private var counterValue: Int = 1

    /// The original NSImage, kept for rendering the base image in the canvas.
    private let baseImage: NSImage

    // MARK: - Initialization

    init(image: NSImage) {
        self.baseImage = image

        let tiffData = image.tiffRepresentation ?? Data()
        let pngData: Data
        if let bitmap = NSBitmapImageRep(data: tiffData) {
            pngData = bitmap.representation(using: .png, properties: [:]) ?? tiffData
        } else {
            pngData = tiffData
        }

        let doc = AnnotationDocument(
            imageData: pngData,
            canvasSize: image.size
        )
        _document = State(initialValue: doc)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            AnnotationToolbar(
                selectedTool: $selectedTool,
                selectedColor: $selectedColor,
                strokeWidth: $strokeWidth,
                onUndo: undo,
                onRedo: redo,
                onCopy: copyToClipboard,
                onSave: save,
                canUndo: !undoStack.isEmpty,
                canRedo: !redoStack.isEmpty
            )

            Divider()

            ScrollView([.horizontal, .vertical]) {
                AnnotationCanvasView(
                    baseImage: baseImage,
                    annotations: document.annotations,
                    selectedTool: selectedTool,
                    selectedColor: selectedColor,
                    strokeWidth: strokeWidth,
                    counterValue: counterValue,
                    onAnnotationCreated: { annotation in
                        commitAnnotation(annotation)
                    }
                )
                .padding(20)
            }
        }
        .frame(minWidth: 560, minHeight: 400)
    }

    // MARK: - Annotation Commit

    /// Pushes the current annotation state onto the undo stack and appends
    /// the new annotation.
    private func commitAnnotation(_ annotation: AnnotationDocument.Annotation) {
        undoStack.append(document.annotations)
        redoStack.removeAll()
        document.annotations.append(annotation)

        // Increment counter for next counter annotation.
        if annotation.type == .counter {
            counterValue += 1
        }
    }

    // MARK: - Undo / Redo

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document.annotations)
        document.annotations = previous
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document.annotations)
        document.annotations = next
    }

    // MARK: - Copy to Clipboard

    private func copyToClipboard() {
        guard let finalImage = renderFinalImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([finalImage])
    }

    // MARK: - Save

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "annotated-screenshot.png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let finalImage = renderFinalImage(),
              let tiffData = finalImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return }

        let isPNG = url.pathExtension.lowercased() == "png"
        let fileType: NSBitmapImageRep.FileType = isPNG ? .png : .jpeg
        guard let data = bitmap.representation(using: fileType, properties: [:]) else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("AnnotationEditorView: failed to save — \(error)")
        }
    }

    // MARK: - Render Final Image

    /// Composites the base image and all annotations into a single `NSImage`
    /// using ``AnnotationRenderer``.
    private func renderFinalImage() -> NSImage? {
        let pointSize = document.canvasSize
        guard pointSize.width > 0, pointSize.height > 0 else { return nil }

        // Get actual pixel dimensions from the bitmap rep for full-resolution export.
        guard let tiffData = baseImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else { return nil }

        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        let scaleX = CGFloat(pixelWidth) / pointSize.width
        let scaleY = CGFloat(pixelHeight) / pointSize.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Flip context to match top-left origin (matches SwiftUI coordinate system).
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: 1, y: -1)

        // Scale context so point-based annotations map to pixel coordinates.
        ctx.scaleBy(x: scaleX, y: scaleY)

        // Draw base image.
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: pointSize))

        // Draw all annotations (in point coordinates, scaled by context).
        for annotation in document.annotations {
            AnnotationRenderer.draw(annotation, in: ctx, baseImage: cgImage)
        }

        guard let resultCGImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: resultCGImage, size: pointSize)
    }
}
