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

    /// Called when the user finishes a drag and a new annotation should be committed.
    var onAnnotationCreated: (AnnotationDocument.Annotation) -> Void

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
        }
        .frame(
            width: baseImage.size.width,
            height: baseImage.size.height
        )
        .gesture(dragGesture)
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let location = value.location

                if dragStart == nil {
                    dragStart = value.startLocation
                    if selectedTool == .pencil || selectedTool == .highlighter {
                        freehandPoints = [value.startLocation]
                    }
                }

                dragEnd = location

                if selectedTool == .pencil || selectedTool == .highlighter {
                    freehandPoints.append(location)
                }
            }
            .onEnded { value in
                guard let start = dragStart else { return }
                let end = value.location

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
            }
    }

    // MARK: - Annotation Factory

    /// Builds an ``AnnotationDocument/Annotation`` from the current tool settings
    /// and the given drag coordinates.
    private func makeAnnotation(
        start: CGPoint,
        end: CGPoint,
        points: [CGPoint]?
    ) -> AnnotationDocument.Annotation {
        AnnotationDocument.Annotation(
            id: UUID(),
            type: selectedTool,
            startPoint: start,
            endPoint: end,
            points: points,
            color: selectedColor,
            strokeWidth: strokeWidth,
            text: selectedTool == .text ? "Text" : nil,
            fontSize: selectedTool == .text ? 16 : (selectedTool == .counter ? 14 : nil),
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
            drawArrow(annotation, in: &context, color: swiftUIColor)

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
            drawText(annotation, in: &context, color: swiftUIColor)

        case .counter:
            drawCounter(annotation, in: &context, color: swiftUIColor)

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
        shaft.addLine(to: end)
        context.stroke(
            shaft,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )

        // Arrowhead
        let angle = atan2(end.y - start.y, end.x - start.x)
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
