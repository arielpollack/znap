import SwiftUI

/// Holds a reference to the ``MagnificationHostView`` so that zoom actions
/// can be invoked reliably from toolbar button closures.
private class ZoomHostHolder {
    var host: MagnificationHostView?
}

/// The root SwiftUI view for the annotation editor.
///
/// Combines ``AnnotationToolbar`` (top) with a scrollable ``AnnotationCanvasView``
/// (below). Manages undo/redo state, save, and copy-to-clipboard.
struct AnnotationEditorView: View {

    // MARK: - State

    @State private var document: AnnotationDocument
    @State private var selectedTool: AnnotationDocument.AnnotationType = .arrow
    @State private var selectedColor: AnnotationDocument.CodableColor = Self.loadSavedColor()
    @State private var strokeWidth: CGFloat = 3
    @State private var undoStack: [[AnnotationDocument.Annotation]] = []
    @State private var redoStack: [[AnnotationDocument.Annotation]] = []
    @State private var counterValue: Int = 1
    @State private var selectedAnnotationID: UUID?
    @State private var hoveredAnnotationID: UUID?
    /// Suppresses spurious undo pushes when loading a selected annotation's properties.
    @State private var isLoadingSelection = false
    @State private var zoomLevel: CGFloat = 1.0
    /// Class-based holder so toolbar closures always see the current host reference.
    private let zoomHostHolder = ZoomHostHolder()
    @State private var backgroundConfig: BackgroundRenderer.Config

    /// The original NSImage, kept for rendering the base image in the canvas.
    private let baseImage: NSImage

    /// The title of the window that was captured (e.g., app name). Empty if unknown.
    private let capturedWindowTitle: String

    /// The initial magnification: fit-to-window for large captures, 1.0 otherwise.
    private let initialMagnification: CGFloat

    // MARK: - Initialization

    init(image: NSImage, windowTitle: String = "") {
        self.baseImage = image
        self.capturedWindowTitle = windowTitle

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

        // Compute fit-to-window zoom so the captured image is always fully visible.
        // Mirror the window sizing logic from AnnotationEditorWindow.
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let chromeHeight: CGFloat = 80
        let toolbarMinWidth: CGFloat = 580

        var bgConfig = BackgroundRenderer.Config.load()
        bgConfig.windowTitle = windowTitle
        let bgExtra: CGFloat = bgConfig.enabled ? bgConfig.padding * 2 : 0
        let headerExtra: CGFloat = bgConfig.enabled && bgConfig.showWindowHeader ? BackgroundRenderer.headerHeight : 0

        // Full document size (what the scroll view contains at magnification 1).
        var docW = image.size.width + bgExtra
        var docH = image.size.height + bgExtra + headerExtra

        // Apply aspect ratio constraint to document size.
        if bgConfig.enabled, let ratio = bgConfig.aspectRatio?.value {
            let currentRatio = docW / docH
            if currentRatio > ratio {
                docH = docW / ratio
            } else if currentRatio < ratio {
                docW = docH * ratio
            }
        }

        // Viewport = window size (capped to screen) minus chrome.
        let maxW = screenFrame.width - 40
        let maxH = screenFrame.height - 40
        let viewportW = min(max(docW, toolbarMinWidth), maxW)
        let viewportH = min(docH + chromeHeight, maxH) - chromeHeight

        if docW > viewportW || docH > viewportH {
            let fitScale = min(viewportW / docW, viewportH / docH)
            self.initialMagnification = max(fitScale, 0.1)
        } else {
            self.initialMagnification = 1.0
        }

        _backgroundConfig = State(initialValue: bgConfig)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            AnnotationToolbar(
                selectedTool: $selectedTool,
                selectedColor: $selectedColor,
                strokeWidth: $strokeWidth,
                backgroundConfig: $backgroundConfig,
                onUndo: undo,
                onRedo: redo,
                onCopy: copyToClipboard,
                onSave: save,
                canUndo: !undoStack.isEmpty,
                canRedo: !redoStack.isEmpty,
                zoomLevel: zoomLevel,
                onZoomIn: { zoomHostHolder.host?.zoomIn() },
                onZoomOut: { zoomHostHolder.host?.zoomOut() },
                onZoomToFit: { zoomHostHolder.host?.zoomToFit() },
                onZoomToActualSize: { zoomHostHolder.host?.zoomToActualSize() }
            )

            Divider()

            GeometryReader { viewportProxy in
                ScrollView([.horizontal, .vertical]) {
                    canvasWithBackground
                        .frame(
                            minWidth: viewportProxy.size.width,
                            minHeight: viewportProxy.size.height,
                            alignment: .center
                        )
                        .background(
                            MagnificationHost(
                                initialMagnification: initialMagnification,
                                contentSize: computeDocumentSize(for: backgroundConfig),
                                onMagnificationChanged: { mag in
                                    zoomLevel = mag
                                },
                                onHostReady: { host in
                                    zoomHostHolder.host = host
                                }
                            )
                            .frame(width: 0, height: 0)
                        )
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 580, minHeight: 400)
        .onChange(of: selectedColor) { newColor in
            applyPropertyToSelected { $0.color = newColor }
            Self.saveColor(newColor)
        }
        .onChange(of: strokeWidth) { newWidth in
            applyPropertyToSelected { $0.strokeWidth = newWidth }
        }
        .onReceive(NotificationCenter.default.publisher(for: .annotationUndo)) { _ in undo() }
        .onReceive(NotificationCenter.default.publisher(for: .annotationRedo)) { _ in redo() }
        .onReceive(NotificationCenter.default.publisher(for: .annotationCopy)) { _ in copyToClipboard() }
        .onReceive(NotificationCenter.default.publisher(for: .annotationSave)) { _ in save() }
        .onReceive(NotificationCenter.default.publisher(for: .annotationDelete)) { _ in deleteSelectedAnnotation() }
        .onReceive(NotificationCenter.default.publisher(for: .annotationSelectTool)) { notification in
            if let rawValue = notification.userInfo?["tool"] as? String,
               let tool = AnnotationDocument.AnnotationType(rawValue: rawValue) {
                selectedTool = tool
            }
        }
        .onChange(of: backgroundConfig) { [backgroundConfig] newConfig in
            newConfig.save()
            // Only zoom when canvas size changes significantly.
            let sizeChanged = backgroundConfig.enabled != newConfig.enabled
                || backgroundConfig.showWindowHeader != newConfig.showWindowHeader
                || backgroundConfig.aspectRatio != newConfig.aspectRatio
            if sizeChanged {
                // Compute the new content size directly (layout hasn't updated yet).
                let newSize = computeDocumentSize(for: newConfig)
                zoomHostHolder.host?.setContentSize(newSize)
                DispatchQueue.main.async {
                    zoomHostHolder.host?.zoomToFit()
                }
            }
        }
    }

    // MARK: - Canvas with Background

    /// Wraps the annotation canvas with an optional visual background preview.
    @ViewBuilder
    private var canvasWithBackground: some View {
        let canvas = AnnotationCanvasView(
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

        if backgroundConfig.enabled {
            let extraPadding = aspectRatioPadding
            VStack(spacing: 0) {
                if backgroundConfig.showWindowHeader {
                    windowHeaderView
                }
                canvas
            }
            .clipShape(RoundedRectangle(cornerRadius: backgroundConfig.showWindowHeader ? 10 : backgroundConfig.cornerRadius))
            .shadow(
                color: backgroundConfig.addShadow ? .black.opacity(0.4) : .clear,
                radius: backgroundConfig.addShadow ? 20 : 0,
                y: backgroundConfig.addShadow ? 4 : 0
            )
            .padding(.horizontal, backgroundConfig.padding + extraPadding.width)
            .padding(.vertical, backgroundConfig.padding + extraPadding.height)
            .background(backgroundGradient)
        } else {
            canvas
        }
    }

    /// Dummy macOS window header with traffic lights and centered title.
    private var windowHeaderView: some View {
        ZStack {
            Color(nsColor: backgroundConfig.headerStyle.backgroundColor)

            HStack(spacing: 8) {
                Circle().fill(Color(red: 1.0, green: 0.373, blue: 0.341)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.996, green: 0.737, blue: 0.180)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.157, green: 0.784, blue: 0.251)).frame(width: 12, height: 12)
                Spacer()
            }
            .padding(.leading, 8)

            Text(backgroundConfig.windowTitle)
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: backgroundConfig.headerStyle.textColor))
        }
        .frame(height: 28)
    }

    /// Extra padding per axis to satisfy the aspect ratio constraint.
    /// Mirrors the logic in ``BackgroundRenderer/render``.
    private var aspectRatioPadding: CGSize {
        guard let ratio = backgroundConfig.aspectRatio?.value else { return .zero }
        let headerH = backgroundConfig.showWindowHeader ? BackgroundRenderer.headerHeight : 0
        let canvasW = baseImage.size.width + backgroundConfig.padding * 2
        let canvasH = baseImage.size.height + headerH + backgroundConfig.padding * 2
        let currentRatio = canvasW / canvasH
        if currentRatio > ratio {
            // Too wide — add vertical padding
            let newH = canvasW / ratio
            return CGSize(width: 0, height: (newH - canvasH) / 2)
        } else if currentRatio < ratio {
            // Too tall — add horizontal padding
            let newW = canvasH * ratio
            return CGSize(width: (newW - canvasW) / 2, height: 0)
        }
        return .zero
    }

    /// Computes the total document size for a given config (for zoom-to-fit calculations).
    private func computeDocumentSize(for config: BackgroundRenderer.Config) -> CGSize {
        guard config.enabled else { return baseImage.size }
        let headerH = config.showWindowHeader ? BackgroundRenderer.headerHeight : 0
        var w = baseImage.size.width + config.padding * 2
        var h = baseImage.size.height + headerH + config.padding * 2
        if let ratio = config.aspectRatio?.value {
            let currentRatio = w / h
            if currentRatio > ratio {
                h = w / ratio
            } else if currentRatio < ratio {
                w = h * ratio
            }
        }
        return CGSize(width: w, height: h)
    }

    /// The background gradient or solid color for the live preview.
    @ViewBuilder
    private var backgroundGradient: some View {
        switch backgroundConfig.backgroundType {
        case .gradient(let preset):
            let index = max(0, min(preset, BackgroundRenderer.gradientPresets.count - 1))
            let colors = BackgroundRenderer.gradientPresets[index]
            LinearGradient(
                colors: [Color(nsColor: colors.0), Color(nsColor: colors.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .solid(let c):
            Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        }
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

        guard let cgImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        // Pre-apply all image filter annotations (pixelate, blur, spotlight)
        // cumulatively so they compose correctly instead of overwriting each other.
        let filterAnnotations = document.annotations.filter {
            AnnotationRenderer.imageFilterTypes.contains($0.type)
        }
        let filteredBase = AnnotationRenderer.applyImageFilters(
            filterAnnotations, to: cgImage, canvasSize: pointSize
        )

        let pixelWidth = filteredBase.width
        let pixelHeight = filteredBase.height
        let scaleX = CGFloat(pixelWidth) / pointSize.width
        let scaleY = CGFloat(pixelHeight) / pointSize.height

        // Draw at pixel dimensions to preserve full Retina resolution.
        let pixelSize = NSSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        let result = NSImage(size: pixelSize)

        result.lockFocus()

        // Draw filtered base image using NSImage.draw which handles coordinate systems.
        let filteredNSImage = NSImage(cgImage: filteredBase, size: pixelSize)
        filteredNSImage.draw(
            in: NSRect(origin: .zero, size: pixelSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        // Draw non-filter annotations via CGContext.
        if let ctx = NSGraphicsContext.current?.cgContext {
            // lockFocus uses bottom-left origin; annotations use top-left (SwiftUI).
            ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
            ctx.scaleBy(x: 1, y: -1)
            ctx.scaleBy(x: scaleX, y: scaleY)

            for annotation in document.annotations where !AnnotationRenderer.imageFilterTypes.contains(annotation.type) {
                AnnotationRenderer.draw(annotation, in: ctx, baseImage: filteredBase, canvasSize: pointSize)
            }
        }

        result.unlockFocus()

        // Set point size for display/background rendering.
        result.size = pointSize

        // Apply background if enabled.
        if backgroundConfig.enabled {
            return BackgroundRenderer.render(screenshot: result, config: backgroundConfig)
        }

        return result
    }

    // MARK: - Color Persistence

    private static let colorDefaultsKey = "annotationSelectedColor"

    private static func loadSavedColor() -> AnnotationDocument.CodableColor {
        guard let data = UserDefaults.standard.data(forKey: colorDefaultsKey),
              let color = try? JSONDecoder().decode(AnnotationDocument.CodableColor.self, from: data)
        else { return .defaultRed }
        return color
    }

    private static func saveColor(_ color: AnnotationDocument.CodableColor) {
        if let data = try? JSONEncoder().encode(color) {
            UserDefaults.standard.set(data, forKey: colorDefaultsKey)
        }
    }
}

// MARK: - Viewport Size Tracking