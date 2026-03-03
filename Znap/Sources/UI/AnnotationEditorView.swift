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
    @State private var selectedAnnotationID: UUID?
    @State private var hoveredAnnotationID: UUID?
    /// Suppresses spurious undo pushes when loading a selected annotation's properties.
    @State private var isLoadingSelection = false
    @State private var zoomLevel: CGFloat = 1.0
    @State private var zoomHost: MagnificationHostView?

    /// The original NSImage, kept for rendering the base image in the canvas.
    private let baseImage: NSImage

    /// The initial magnification: fit-to-window for large captures, 1.0 otherwise.
    private let initialMagnification: CGFloat

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

        // Compute fit-to-window for large captures.
        // Use the main screen's visible frame minus toolbar/chrome as reference.
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let toolbarHeight: CGFloat = 60
        let padding: CGFloat = 80  // ScrollView padding + window chrome
        let availableWidth = screenFrame.width - padding
        let availableHeight = screenFrame.height - toolbarHeight - padding

        let imgW = image.size.width
        let imgH = image.size.height

        if imgW > availableWidth || imgH > availableHeight {
            // Image is larger than the viewport — fit to window.
            let fitScale = min(availableWidth / imgW, availableHeight / imgH)
            self.initialMagnification = max(fitScale, 0.1)
        } else {
            self.initialMagnification = 1.0
        }
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
                canRedo: !redoStack.isEmpty,
                zoomLevel: zoomLevel,
                onZoomIn: { zoomHost?.zoomIn() },
                onZoomOut: { zoomHost?.zoomOut() },
                onZoomToFit: { zoomHost?.zoomToFit() },
                onZoomToActualSize: { zoomHost?.zoomToActualSize() }
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
                    selectedAnnotationID: selectedAnnotationID,
                    onAnnotationCreated: { annotation in
                        commitAnnotation(annotation)
                    },
                    onAnnotationSelected: { id in
                        selectedAnnotationID = id
                        // Load selected annotation's properties into toolbar.
                        if let annotation = document.annotations.first(where: { $0.id == id }) {
                            isLoadingSelection = true
                            selectedColor = annotation.color
                            strokeWidth = annotation.strokeWidth
                            isLoadingSelection = false
                        }
                    },
                    onSelectionCleared: {
                        selectedAnnotationID = nil
                    },
                    onAnnotationMoved: { id, delta in
                        moveAnnotation(id, by: delta)
                    },
                    onMoveStarted: {
                        undoStack.append(document.annotations)
                        redoStack.removeAll()
                    },
                    onArrowHandleDragged: { id, handle, position in
                        guard let index = document.annotations.firstIndex(where: { $0.id == id }) else { return }
                        switch handle {
                        case .start:
                            document.annotations[index].startPoint = position
                        case .end:
                            document.annotations[index].endPoint = position
                        case .curve:
                            document.annotations[index].curveControlPoint = position
                        }
                    },
                    onHandleDragStarted: {
                        undoStack.append(document.annotations)
                        redoStack.removeAll()
                    },
                    onCurveHandleReset: { id in
                        guard let index = document.annotations.firstIndex(where: { $0.id == id }) else { return }
                        undoStack.append(document.annotations)
                        redoStack.removeAll()
                        document.annotations[index].curveControlPoint = nil
                    },
                    onResizeStarted: {
                        undoStack.append(document.annotations)
                        redoStack.removeAll()
                    },
                    onTextResized: { id, newFontSize in
                        guard let index = document.annotations.firstIndex(where: { $0.id == id }) else { return }
                        document.annotations[index].fontSize = newFontSize
                    },
                    hoveredAnnotationID: hoveredAnnotationID,
                    onHoverChanged: { id in
                        hoveredAnnotationID = id
                    }
                )
                .padding(20)
                .background(
                    MagnificationHost(
                        initialMagnification: initialMagnification,
                        onMagnificationChanged: { mag in
                            zoomLevel = mag
                        },
                        onHostReady: { host in
                            zoomHost = host
                        }
                    )
                    .frame(width: 0, height: 0)
                )
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .onChange(of: selectedColor) { newColor in
            applyPropertyToSelected { $0.color = newColor }
        }
        .onChange(of: strokeWidth) { newWidth in
            applyPropertyToSelected { $0.strokeWidth = newWidth }
        }
        .onReceive(NotificationCenter.default.publisher(for: .annotationUndo)) { _ in undo() }
        .onReceive(NotificationCenter.default.publisher(for: .annotationRedo)) { _ in redo() }
        .onReceive(NotificationCenter.default.publisher(for: .annotationCopy)) { _ in copyToClipboard() }
        .onReceive(NotificationCenter.default.publisher(for: .annotationSave)) { _ in save() }
        .onReceive(NotificationCenter.default.publisher(for: .annotationDelete)) { _ in deleteSelectedAnnotation() }
    }

    // MARK: - Annotation Commit

    /// Pushes the current annotation state onto the undo stack and appends
    /// the new annotation.
    private func commitAnnotation(_ annotation: AnnotationDocument.Annotation) {
        undoStack.append(document.annotations)
        redoStack.removeAll()
        document.annotations.append(annotation)
        selectedAnnotationID = annotation.id

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

    // MARK: - Selection Actions

    private func applyPropertyToSelected(_ mutation: (inout AnnotationDocument.Annotation) -> Void) {
        guard !isLoadingSelection,
              let id = selectedAnnotationID,
              let index = document.annotations.firstIndex(where: { $0.id == id }) else { return }
        undoStack.append(document.annotations)
        redoStack.removeAll()
        mutation(&document.annotations[index])
    }

    private func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationID else { return }
        undoStack.append(document.annotations)
        redoStack.removeAll()
        document.annotations.removeAll { $0.id == id }
        selectedAnnotationID = nil
    }

    private func moveAnnotation(_ id: UUID, by delta: CGPoint) {
        guard let index = document.annotations.firstIndex(where: { $0.id == id }) else { return }
        document.annotations[index].startPoint.x += delta.x
        document.annotations[index].startPoint.y += delta.y
        document.annotations[index].endPoint.x += delta.x
        document.annotations[index].endPoint.y += delta.y
        if var points = document.annotations[index].points {
            for i in points.indices {
                points[i].x += delta.x
                points[i].y += delta.y
            }
            document.annotations[index].points = points
        }
        if var cp = document.annotations[index].curveControlPoint {
            cp.x += delta.x
            cp.y += delta.y
            document.annotations[index].curveControlPoint = cp
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
