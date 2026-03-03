import SwiftUI

/// A SwiftUI `Canvas` view that draws the base screenshot plus all annotations,
/// including a live in-progress annotation as the user drags.
///
/// This is the **preview** drawing path. The final export uses
/// ``AnnotationRenderer`` (CoreGraphics) instead.
struct AnnotationCanvasView: View {

    // MARK: - Properties

    let baseImage: NSImage
    let annotations: [AnnotationDocument.Annotation]
    let selectedTool: AnnotationDocument.AnnotationType
    let selectedColor: AnnotationDocument.CodableColor
    let strokeWidth: CGFloat
    let counterValue: Int

    /// The ID of the currently selected annotation, if any.
    var selectedAnnotationID: UUID?

    /// Called when the user finishes a drag and a new annotation should be committed.
    var onAnnotationCreated: (AnnotationDocument.Annotation) -> Void

    /// Called when an annotation is tapped to select it.
    var onAnnotationSelected: ((UUID) -> Void)?

    /// Called when clicking on empty space to clear selection.
    var onSelectionCleared: (() -> Void)?

    /// Called when a selected annotation is dragged (passes delta).
    var onAnnotationMoved: ((UUID, CGPoint) -> Void)?

    /// Called when a drag-move sequence starts (for undo snapshot).
    var onMoveStarted: (() -> Void)?

    /// Called when an arrow handle is dragged (passes annotation ID, handle, new position).
    var onArrowHandleDragged: ((UUID, AnnotationHitTesting.ArrowHandle, CGPoint) -> Void)?

    /// Called when a handle drag sequence starts (for undo snapshot).
    var onHandleDragStarted: (() -> Void)?

    /// Called when the curve handle is double-clicked to reset.
    var onCurveHandleReset: ((UUID) -> Void)?

    // MARK: - State

    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var freehandPoints: [CGPoint] = []

    // MARK: - Body

    var body: some View {
        Canvas { context, size in
            // 1. Draw base image.
            let imageRect = CGRect(origin: .zero, size: size)
            context.draw(Image(nsImage: baseImage), in: imageRect)

            // 2. Draw committed annotations.
            for annotation in annotations {
                drawAnnotation(annotation, in: &context, canvasSize: size)
            }

            // 3. Draw in-progress annotation.
            if let start = dragStart, let end = dragEnd {
                let inProgress = makeAnnotation(
                    start: start,
                    end: end,
                    points: freehandPoints.isEmpty ? nil : freehandPoints
                )
                drawAnnotation(inProgress, in: &context, canvasSize: size)
            }

            // 4. Draw selection indicator.
            if let selID = selectedAnnotationID,
               let annotation = annotations.first(where: { $0.id == selID }) {
                let bbox = AnnotationHitTesting.boundingBox(for: annotation)
                let selPath = Path(bbox)
                context.stroke(
                    selPath,
                    with: .color(.blue.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])
                )

                // Arrow handle indicators.
                if annotation.type == .arrow {
                    // Endpoint circles.
                    drawHandle(circle: annotation.startPoint, in: &context)
                    drawHandle(circle: annotation.endPoint, in: &context)

                    // Curve handle (square).
                    let curvePoint = annotation.curveControlPoint ?? CGPoint(
                        x: (annotation.startPoint.x + annotation.endPoint.x) / 2,
                        y: (annotation.startPoint.y + annotation.endPoint.y) / 2
                    )
                    let isGhost = annotation.curveControlPoint == nil
                    drawHandle(square: curvePoint, ghost: isGhost, in: &context)

                    // Guide line from midpoint to control point when curve is active.
                    if annotation.curveControlPoint != nil {
                        let mid = CGPoint(
                            x: (annotation.startPoint.x + annotation.endPoint.x) / 2,
                            y: (annotation.startPoint.y + annotation.endPoint.y) / 2
                        )
                        var guideLine = Path()
                        guideLine.move(to: mid)
                        guideLine.addLine(to: curvePoint)
                        context.stroke(
                            guideLine,
                            with: .color(.blue.opacity(0.3)),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                    }
                }
            }
        }
        .frame(
            width: baseImage.size.width,
            height: baseImage.size.height
        )
        .overlay(
            AnnotationMouseOverlay(
                selectedTool: selectedTool,
                textColor: NSColor(
                    red: selectedColor.red,
                    green: selectedColor.green,
                    blue: selectedColor.blue,
                    alpha: selectedColor.alpha
                ),
                fontSize: selectedTool == .handwriting ? 24 : 16,
                fontName: selectedTool == .handwriting ? "Bradley Hand" : nil,
                annotations: annotations,
                selectedAnnotationID: selectedAnnotationID,
                onDragStarted: { location in
                    dragStart = location
                    dragEnd = location
                    if selectedTool == .pencil || selectedTool == .highlighter {
                        freehandPoints = [location]
                    }
                },
                onDragChanged: { location in
                    dragEnd = location
                    if selectedTool == .pencil || selectedTool == .highlighter {
                        freehandPoints.append(location)
                    }
                },
                onDragEnded: { start, end in
                    let annotation = makeAnnotation(
                        start: start,
                        end: end,
                        points: freehandPoints.isEmpty ? nil : freehandPoints
                    )
                    onAnnotationCreated(annotation)

                    // Reset drag state.
                    dragStart = nil
                    dragEnd = nil
                    freehandPoints = []
                },
                onTextCommitted: { position, text in
                    let isHandwriting = selectedTool == .handwriting
                    let annotation = AnnotationDocument.Annotation(
                        id: UUID(),
                        type: isHandwriting ? .handwriting : .text,
                        startPoint: position,
                        endPoint: position,
                        points: nil,
                        color: selectedColor,
                        strokeWidth: strokeWidth,
                        text: text,
                        fontSize: isHandwriting ? 24 : 16,
                        counterValue: nil,
                        isFilled: false
                    )
                    onAnnotationCreated(annotation)
                },
                onAnnotationSelected: { id in
                    onAnnotationSelected?(id)
                },
                onSelectionCleared: {
                    onSelectionCleared?()
                },
                onAnnotationMoved: { id, delta in
                    onAnnotationMoved?(id, delta)
                },
                onMoveStarted: {
                    onMoveStarted?()
                },
                onArrowHandleDragged: { id, handle, position in
                    onArrowHandleDragged?(id, handle, position)
                },
                onHandleDragStarted: {
                    onHandleDragStarted?()
                },
                onCurveHandleReset: { id in
                    onCurveHandleReset?(id)
                }
            )
        )
    }

    // MARK: - Handle Drawing

    private func drawHandle(circle point: CGPoint, in context: inout GraphicsContext) {
        let r: CGFloat = 5
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(.white))
        context.stroke(path, with: .color(.blue), lineWidth: 2)
    }

    private func drawHandle(square point: CGPoint, ghost: Bool, in context: inout GraphicsContext) {
        let r: CGFloat = 5
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
        let path = Path(rect)
        let fillColor: Color = ghost ? .gray.opacity(0.3) : .white
        let strokeColor: Color = ghost ? .gray.opacity(0.5) : .blue
        context.fill(path, with: .color(fillColor))
        context.stroke(path, with: .color(strokeColor), lineWidth: 2)
    }

    // MARK: - Annotation Factory

    /// Builds an ``AnnotationDocument/Annotation`` from the current tool settings
    /// and the given drag coordinates.
    private func makeAnnotation(
        start: CGPoint,
        end: CGPoint,
        points: [CGPoint]?
    ) -> AnnotationDocument.Annotation {
        let isTextTool = selectedTool == .text || selectedTool == .handwriting
        let textFontSize: CGFloat = selectedTool == .handwriting ? 24 : 16
        return AnnotationDocument.Annotation(
            id: UUID(),
            type: selectedTool,
            startPoint: start,
            endPoint: end,
            points: points,
            color: selectedColor,
            strokeWidth: strokeWidth,
            text: isTextTool ? "Text" : nil,
            fontSize: isTextTool ? textFontSize : (selectedTool == .counter ? 14 : nil),
            counterValue: selectedTool == .counter ? counterValue : nil,
            isFilled: selectedTool == .filledRectangle
        )
    }

    // MARK: - Canvas Drawing

    /// Draws a single annotation using SwiftUI's `GraphicsContext`.
    ///
    /// This mirrors ``AnnotationRenderer/draw(_:in:baseImage:)`` but uses
    /// SwiftUI drawing primitives instead of CoreGraphics.
    private func drawAnnotation(
        _ annotation: AnnotationDocument.Annotation,
        in context: inout GraphicsContext,
        canvasSize: CGSize
    ) {
        let swiftUIColor = Color(
            red: annotation.color.red,
            green: annotation.color.green,
            blue: annotation.color.blue,
            opacity: annotation.color.alpha
        )

        switch annotation.type {
        case .arrow:
            context.drawLayer { ctx in
                ctx.addFilter(.shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2))
                drawArrow(annotation, in: &ctx, color: swiftUIColor)
            }

        case .rectangle:
            let rect = AnnotationRenderer.rectFromPoints(
                annotation.startPoint, annotation.endPoint
            )
            let path = Path(rect)
            context.stroke(
                path,
                with: .color(swiftUIColor),
                lineWidth: annotation.strokeWidth
            )

        case .filledRectangle:
            let rect = AnnotationRenderer.rectFromPoints(
                annotation.startPoint, annotation.endPoint
            )
            let path = Path(rect)
            context.fill(path, with: .color(swiftUIColor))

        case .ellipse:
            let rect = AnnotationRenderer.rectFromPoints(
                annotation.startPoint, annotation.endPoint
            )
            let path = Path(ellipseIn: rect)
            context.stroke(
                path,
                with: .color(swiftUIColor),
                lineWidth: annotation.strokeWidth
            )

        case .line:
            var path = Path()
            path.move(to: annotation.startPoint)
            path.addLine(to: annotation.endPoint)
            context.stroke(
                path,
                with: .color(swiftUIColor),
                style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round)
            )

        case .pencil:
            drawFreehand(annotation, in: &context, color: swiftUIColor, opacity: 1.0, widthMultiplier: 1)

        case .highlighter:
            drawFreehand(annotation, in: &context, color: swiftUIColor, opacity: 0.4, widthMultiplier: 4)

        case .text:
            context.drawLayer { ctx in
                ctx.addFilter(.shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2))
                drawText(annotation, in: &ctx, color: swiftUIColor)
            }

        case .handwriting:
            context.drawLayer { ctx in
                ctx.addFilter(.shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2))
                drawHandwriting(annotation, in: &ctx, color: swiftUIColor)
            }

        case .counter:
            context.drawLayer { ctx in
                ctx.addFilter(.shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2))
                drawCounter(annotation, in: &ctx, color: swiftUIColor)
            }

        case .pixelate, .blur, .spotlight:
            // Preview: draw a dashed rectangle outline.
            let rect = AnnotationRenderer.rectFromPoints(
                annotation.startPoint, annotation.endPoint
            )
            let dashedPath = Path(rect)
            context.stroke(
                dashedPath,
                with: .color(swiftUIColor),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
            )
        }
    }

    // MARK: - Arrow Drawing

    private func drawArrow(
        _ annotation: AnnotationDocument.Annotation,
        in context: inout GraphicsContext,
        color: Color
    ) {
        let start = annotation.startPoint
        let end = annotation.endPoint
        let lineWidth = annotation.strokeWidth

        // Shaft
        var shaft = Path()
        shaft.move(to: start)
        if let cp = annotation.curveControlPoint {
            shaft.addQuadCurve(to: end, control: cp)
        } else {
            shaft.addLine(to: end)
        }
        context.stroke(
            shaft,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )

        // Arrowhead — compute angle from tangent direction at endpoint.
        let angle: CGFloat
        if let cp = annotation.curveControlPoint {
            angle = atan2(end.y - cp.y, end.x - cp.x)
        } else {
            angle = atan2(end.y - start.y, end.x - start.x)
        }
        let headLength: CGFloat = 15
        let headAngle: CGFloat = .pi / 6

        let left = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        var head = Path()
        head.move(to: left)
        head.addLine(to: end)
        head.addLine(to: right)
        context.stroke(
            head,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    // MARK: - Freehand Drawing

    private func drawFreehand(
        _ annotation: AnnotationDocument.Annotation,
        in context: inout GraphicsContext,
        color: Color,
        opacity: Double,
        widthMultiplier: CGFloat
    ) {
        guard let pts = annotation.points, pts.count >= 2 else { return }

        var path = Path()
        path.move(to: pts[0])
        for i in 1..<pts.count {
            path.addLine(to: pts[i])
        }

        var ctx = context
        ctx.opacity = opacity
        ctx.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: annotation.strokeWidth * widthMultiplier,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    // MARK: - Text Drawing

    private func drawText(
        _ annotation: AnnotationDocument.Annotation,
        in context: inout GraphicsContext,
        color: Color
    ) {
        guard let string = annotation.text, !string.isEmpty else { return }
        let fontSize = annotation.fontSize ?? 16

        let text = Text(string)
            .font(.system(size: fontSize))
            .foregroundColor(color)

        context.draw(
            context.resolve(text),
            at: annotation.startPoint,
            anchor: .topLeading
        )
    }

    // MARK: - Handwriting Drawing

    private func drawHandwriting(
        _ annotation: AnnotationDocument.Annotation,
        in context: inout GraphicsContext,
        color: Color
    ) {
        guard let string = annotation.text, !string.isEmpty else { return }
        let fontSize = annotation.fontSize ?? 24

        let text = Text(string)
            .font(.custom("Bradley Hand", size: fontSize))
            .foregroundColor(color)

        context.draw(
            context.resolve(text),
            at: annotation.startPoint,
            anchor: .topLeading
        )
    }

    // MARK: - Counter Drawing

    private func drawCounter(
        _ annotation: AnnotationDocument.Annotation,
        in context: inout GraphicsContext,
        color: Color
    ) {
        let center = annotation.startPoint
        let radius: CGFloat = 14
        let value = annotation.counterValue ?? 0

        // Filled circle
        let circleRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(Path(ellipseIn: circleRect), with: .color(color))

        // White number text
        let numberText = Text("\(value)")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white)
        context.draw(
            context.resolve(numberText),
            at: center,
            anchor: .center
        )
    }
}

// MARK: - Mouse Event Overlay

/// Uses AppKit's `NSView` to handle mouse events with proper coordinate
/// conversion through the `NSScrollView`'s magnification and scroll offset.
/// This replaces SwiftUI's `DragGesture`, which doesn't account for
/// externally-set `NSScrollView` magnification.
private struct AnnotationMouseOverlay: NSViewRepresentable {

    let selectedTool: AnnotationDocument.AnnotationType
    let textColor: NSColor
    let fontSize: CGFloat
    let fontName: String?
    let annotations: [AnnotationDocument.Annotation]
    let selectedAnnotationID: UUID?
    let onDragStarted: (CGPoint) -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGPoint, CGPoint) -> Void
    let onTextCommitted: (CGPoint, String) -> Void
    let onAnnotationSelected: (UUID) -> Void
    let onSelectionCleared: () -> Void
    let onAnnotationMoved: (UUID, CGPoint) -> Void
    let onMoveStarted: () -> Void
    let onArrowHandleDragged: (UUID, AnnotationHitTesting.ArrowHandle, CGPoint) -> Void
    let onHandleDragStarted: () -> Void
    let onCurveHandleReset: (UUID) -> Void

    func makeNSView(context: Context) -> AnnotationMouseView {
        let view = AnnotationMouseView()
        updateView(view)
        return view
    }

    func updateNSView(_ nsView: AnnotationMouseView, context: Context) {
        let previousTool = nsView.selectedTool
        updateView(nsView)

        // Commit any active text field if the user switched tools.
        let isTextTool = selectedTool == .text || selectedTool == .handwriting
        let wasTextTool = previousTool == .text || previousTool == .handwriting
        if wasTextTool && !isTextTool {
            nsView.commitActiveTextField()
        }
    }

    private func updateView(_ view: AnnotationMouseView) {
        view.selectedTool = selectedTool
        view.textColor = textColor
        view.fontSize = fontSize
        view.fontName = fontName
        view.annotations = annotations
        view.selectedAnnotationID = selectedAnnotationID
        view.onDragStarted = onDragStarted
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onTextCommitted = onTextCommitted
        view.onAnnotationSelected = onAnnotationSelected
        view.onSelectionCleared = onSelectionCleared
        view.onAnnotationMoved = onAnnotationMoved
        view.onMoveStarted = onMoveStarted
        view.onArrowHandleDragged = onArrowHandleDragged
        view.onHandleDragStarted = onHandleDragStarted
        view.onCurveHandleReset = onCurveHandleReset
    }
}

/// An `NSView` that handles mouse events and converts coordinates using
/// AppKit's coordinate chain, which properly accounts for the parent
/// `NSScrollView`'s magnification and scroll offset.
final class AnnotationMouseView: NSView, NSTextFieldDelegate {

    override var isFlipped: Bool { true }

    var selectedTool: AnnotationDocument.AnnotationType = .arrow
    var textColor: NSColor = .red
    var fontSize: CGFloat = 16
    var fontName: String?
    var annotations: [AnnotationDocument.Annotation] = []
    var selectedAnnotationID: UUID?
    var onDragStarted: ((CGPoint) -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint, CGPoint) -> Void)?
    var onTextCommitted: ((CGPoint, String) -> Void)?
    var onAnnotationSelected: ((UUID) -> Void)?
    var onSelectionCleared: (() -> Void)?
    var onAnnotationMoved: ((UUID, CGPoint) -> Void)?
    var onMoveStarted: (() -> Void)?
    var onArrowHandleDragged: ((UUID, AnnotationHitTesting.ArrowHandle, CGPoint) -> Void)?
    var onHandleDragStarted: (() -> Void)?
    var onCurveHandleReset: ((UUID) -> Void)?

    private var mouseDownPoint: CGPoint?
    private var hasDragged = false
    private var activeTextField: NSTextField?
    private var textFieldPosition: CGPoint?

    private enum DragMode {
        case none
        case creating
        case selecting(UUID)          // stores the hit annotation ID directly
        case moving(UUID)
        case draggingHandle(UUID, AnnotationHitTesting.ArrowHandle)
    }

    private var dragMode: DragMode = .none
    private var lastDragLocation: CGPoint?
    private var didPushUndoForDrag = false

    private var isPointPlacementTool: Bool {
        selectedTool == .counter
    }

    private var isTextPlacementTool: Bool {
        selectedTool == .text || selectedTool == .handwriting
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        // Commit any active text field first.
        if activeTextField != nil {
            commitActiveTextField()
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        mouseDownPoint = location
        lastDragLocation = location
        hasDragged = false
        didPushUndoForDrag = false
        dragMode = .none

        // Text tools: just record position, no drag preview.
        if isTextPlacementTool {
            dragMode = .none
            return
        }

        // If there's a selected arrow, check for handle hits first.
        if let selID = selectedAnnotationID,
           let annotation = annotations.first(where: { $0.id == selID }),
           annotation.type == .arrow {
            // Double-click on curve handle → reset curve.
            if event.clickCount == 2,
               annotation.curveControlPoint != nil {
                let curvePoint = annotation.curveControlPoint!
                let dc = hypot(location.x - curvePoint.x, location.y - curvePoint.y)
                if dc <= 12 {
                    onCurveHandleReset?(selID)
                    return
                }
            }

            if let handle = AnnotationHitTesting.hitTestArrowHandle(
                point: location, annotation: annotation
            ) {
                dragMode = .draggingHandle(selID, handle)
                return
            }
        }

        // Hit test all annotations.
        if let hitID = AnnotationHitTesting.findTopmost(at: location, in: annotations) {
            onAnnotationSelected?(hitID)
            dragMode = .selecting(hitID)
            return
        }

        // No hit — clear selection and start creating.
        onSelectionCleared?()

        // Point-placement tools (counter) start immediately on click.
        if isPointPlacementTool {
            dragMode = .creating
            onDragStarted?(location)
            return
        }

        dragMode = .creating
    }

    override func mouseDragged(with event: NSEvent) {
        if isTextPlacementTool { return }
        guard let start = mouseDownPoint else { return }
        let location = convert(event.locationInWindow, from: nil)

        switch dragMode {
        case .selecting(let hitID):
            // Check if we've dragged far enough to start moving.
            let distance = hypot(location.x - start.x, location.y - start.y)
            if distance > 3 {
                dragMode = .moving(hitID)
                if !didPushUndoForDrag {
                    onMoveStarted?()
                    didPushUndoForDrag = true
                }
                let delta = CGPoint(x: location.x - (lastDragLocation?.x ?? start.x),
                                    y: location.y - (lastDragLocation?.y ?? start.y))
                onAnnotationMoved?(hitID, delta)
                lastDragLocation = location
            }

        case .moving(let id):
            let delta = CGPoint(x: location.x - (lastDragLocation?.x ?? start.x),
                                y: location.y - (lastDragLocation?.y ?? start.y))
            onAnnotationMoved?(id, delta)
            lastDragLocation = location

        case .draggingHandle(let id, let handle):
            if !didPushUndoForDrag {
                onHandleDragStarted?()
                didPushUndoForDrag = true
            }
            onArrowHandleDragged?(id, handle, location)

        case .creating:
            if !hasDragged && !isPointPlacementTool {
                let distance = hypot(location.x - start.x, location.y - start.y)
                if distance < 1 { return }
                onDragStarted?(start)
            }
            hasDragged = true
            onDragChanged?(location)

        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }

        if isTextPlacementTool {
            showTextField(at: start)
            mouseDownPoint = nil
            dragMode = .none
            return
        }

        switch dragMode {
        case .creating:
            let end = convert(event.locationInWindow, from: nil)
            if isPointPlacementTool || hasDragged {
                onDragEnded?(start, end)
            }

        case .selecting, .moving, .draggingHandle:
            break

        case .none:
            break
        }

        mouseDownPoint = nil
        hasDragged = false
        dragMode = .none
        lastDragLocation = nil
        didPushUndoForDrag = false
    }

    // MARK: - Inline Text Editing

    private func showTextField(at position: CGPoint) {
        let textField = NSTextField()
        textField.stringValue = ""
        textField.placeholderString = "Type text…"
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBordered = false
        textField.drawsBackground = false
        if let name = fontName, let font = NSFont(name: name, size: fontSize) {
            textField.font = font
        } else {
            textField.font = NSFont.systemFont(ofSize: fontSize)
        }
        textField.textColor = textColor
        textField.focusRingType = .none
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.alignment = .left

        textField.sizeToFit()
        let height = textField.frame.height
        let availableWidth = max(bounds.width - position.x, 100)
        textField.frame = NSRect(
            x: position.x, y: position.y,
            width: availableWidth, height: height
        )

        textField.delegate = self
        addSubview(textField)
        window?.makeFirstResponder(textField)

        activeTextField = textField
        textFieldPosition = position
    }

    func commitActiveTextField() {
        guard let textField = activeTextField, let position = textFieldPosition else { return }
        // Clear first to prevent reentrancy from controlTextDidEndEditing.
        activeTextField = nil
        textFieldPosition = nil

        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        textField.removeFromSuperview()

        if !text.isEmpty {
            onTextCommitted?(position, text)
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ notification: Notification) {
        commitActiveTextField()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            commitActiveTextField()
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            // Escape — cancel without committing.
            let textField = activeTextField
            activeTextField = nil
            textFieldPosition = nil
            textField?.removeFromSuperview()
            return true
        }
        return false
    }
}
