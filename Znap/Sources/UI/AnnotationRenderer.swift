import AppKit
import CoreText

/// Renders annotations into a `CGContext` for final PNG/JPEG export.
///
/// This renderer is the authoritative drawing path for export. It mirrors the
/// preview drawing in ``AnnotationCanvasView`` but uses CoreGraphics directly
/// instead of SwiftUI's `Canvas` / `GraphicsContext`.
enum AnnotationRenderer {

    // MARK: - Public API

    /// Draws a single annotation into the given Core Graphics context.
    ///
    /// - Parameters:
    ///   - annotation: The annotation to render.
    ///   - ctx: The target CGContext.
    ///   - baseImage: The base image, required for pixelate/blur/spotlight effects.
    static func draw(
        _ annotation: AnnotationDocument.Annotation,
        in ctx: CGContext,
        baseImage: CGImage? = nil
    ) {
        let color = annotation.color.cgColor
        let lineWidth = annotation.strokeWidth

        ctx.saveGState()

        switch annotation.type {
        case .arrow:
            drawArrow(annotation, in: ctx, color: color, lineWidth: lineWidth)

        case .rectangle:
            let rect = rectFromPoints(annotation.startPoint, annotation.endPoint)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lineWidth)
            ctx.stroke(rect)

        case .filledRectangle:
            let rect = rectFromPoints(annotation.startPoint, annotation.endPoint)
            ctx.setFillColor(color)
            ctx.fill(rect)

        case .ellipse:
            let rect = rectFromPoints(annotation.startPoint, annotation.endPoint)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lineWidth)
            ctx.strokeEllipse(in: rect)

        case .line:
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.move(to: annotation.startPoint)
            ctx.addLine(to: annotation.endPoint)
            ctx.strokePath()

        case .pencil:
            drawFreehand(annotation, in: ctx, color: color, lineWidth: lineWidth, opacity: 1.0)

        case .highlighter:
            drawFreehand(
                annotation,
                in: ctx,
                color: color,
                lineWidth: lineWidth * 4,
                opacity: 0.4
            )

        case .text:
            drawText(annotation, in: ctx)

        case .counter:
            drawCounter(annotation, in: ctx)

        case .pixelate:
            drawPixelate(annotation, in: ctx, baseImage: baseImage)

        case .blur:
            drawBlur(annotation, in: ctx, baseImage: baseImage)

        case .spotlight:
            drawSpotlight(annotation, in: ctx, baseImage: baseImage)
        }

        ctx.restoreGState()
    }

    // MARK: - Arrow

    private static func drawArrow(
        _ annotation: AnnotationDocument.Annotation,
        in ctx: CGContext,
        color: CGColor,
        lineWidth: CGFloat
    ) {
        let start = annotation.startPoint
        let end = annotation.endPoint

        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Shaft
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()

        // Arrowhead
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 15
        let headAngle: CGFloat = .pi / 6

        let leftX = end.x - headLength * cos(angle - headAngle)
        let leftY = end.y - headLength * sin(angle - headAngle)
        let rightX = end.x - headLength * cos(angle + headAngle)
        let rightY = end.y - headLength * sin(angle + headAngle)

        ctx.move(to: CGPoint(x: leftX, y: leftY))
        ctx.addLine(to: end)
        ctx.addLine(to: CGPoint(x: rightX, y: rightY))
        ctx.strokePath()
    }

    // MARK: - Freehand

    private static func drawFreehand(
        _ annotation: AnnotationDocument.Annotation,
        in ctx: CGContext,
        color: CGColor,
        lineWidth: CGFloat,
        opacity: CGFloat
    ) {
        guard let pts = annotation.points, pts.count >= 2 else { return }

        ctx.setAlpha(opacity)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.move(to: pts[0])
        for i in 1..<pts.count {
            ctx.addLine(to: pts[i])
        }
        ctx.strokePath()
    }

    // MARK: - Text

    private static func drawText(
        _ annotation: AnnotationDocument.Annotation,
        in ctx: CGContext
    ) {
        guard let string = annotation.text, !string.isEmpty else { return }

        let fontSize = annotation.fontSize ?? 16
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let color = annotation.color.nsColor

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]

        let attributedString = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)

        ctx.saveGState()
        // CoreGraphics has Y-up; if the context is flipped we need to account for that.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: annotation.startPoint.x,
                                   y: annotation.startPoint.y + fontSize)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: - Counter

    private static func drawCounter(
        _ annotation: AnnotationDocument.Annotation,
        in ctx: CGContext
    ) {
        let center = annotation.startPoint
        let radius: CGFloat = 14
        let color = annotation.color.cgColor
        let value = annotation.counterValue ?? 0

        // Filled circle
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))

        // White number
        let numberString = "\(value)"
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 14, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let attrString = NSAttributedString(string: numberString, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(
            x: center.x - textBounds.width / 2,
            y: center.y + textBounds.height / 2
        )
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: - Pixelate / Blur / Spotlight

    private static func drawPixelate(
        _ annotation: AnnotationDocument.Annotation,
        in ctx: CGContext,
        baseImage: CGImage?
    ) {
        let rect = rectFromPoints(annotation.startPoint, annotation.endPoint)
        guard let base = baseImage else {
            drawDashedRect(rect, in: ctx, label: "Pixelate")
            return
        }

        if let filtered = ImageFilters.pixelate(image: base, region: rect) {
            // Draw the filtered image over the entire canvas; it already contains the
            // composited result (filter region over original).
            let fullRect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
            ctx.draw(filtered, in: fullRect)
        }
    }

    private static func drawBlur(
        _ annotation: AnnotationDocument.Annotation,
        in ctx: CGContext,
        baseImage: CGImage?
    ) {
        let rect = rectFromPoints(annotation.startPoint, annotation.endPoint)
        guard let base = baseImage else {
            drawDashedRect(rect, in: ctx, label: "Blur")
            return
        }

        if let filtered = ImageFilters.blur(image: base, region: rect) {
            let fullRect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
            ctx.draw(filtered, in: fullRect)
        }
    }

    private static func drawSpotlight(
        _ annotation: AnnotationDocument.Annotation,
        in ctx: CGContext,
        baseImage: CGImage?
    ) {
        let rect = rectFromPoints(annotation.startPoint, annotation.endPoint)
        guard let base = baseImage else {
            drawDashedRect(rect, in: ctx, label: "Spotlight")
            return
        }

        if let filtered = ImageFilters.spotlight(image: base, region: rect) {
            let fullRect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
            ctx.draw(filtered, in: fullRect)
        }
    }

    // MARK: - Dashed Rect Placeholder

    /// Draws a dashed rectangle with an optional centred label — used as a
    /// placeholder when the base image is not available for CIFilter effects.
    private static func drawDashedRect(
        _ rect: CGRect,
        in ctx: CGContext,
        label: String? = nil
    ) {
        ctx.setStrokeColor(CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1))
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.stroke(rect)

        if let label = label {
            let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(red: 1, green: 0.23, blue: 0.19, alpha: 1),
            ]
            let attrString = NSAttributedString(string: label, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)
            let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

            ctx.saveGState()
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = CGPoint(
                x: rect.midX - textBounds.width / 2,
                y: rect.midY + textBounds.height / 2
            )
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
    }

    // MARK: - Helpers

    /// Constructs a normalised (positive width/height) rectangle from two
    /// arbitrary corner points.
    static func rectFromPoints(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}
