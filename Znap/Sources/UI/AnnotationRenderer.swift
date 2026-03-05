import AppKit
import CoreText

/// Renders annotations into a `CGContext` for final PNG/JPEG export.
///
/// This renderer is the authoritative drawing path for export. It mirrors the
/// preview drawing in ``AnnotationCanvasView`` but uses CoreGraphics directly
/// instead of SwiftUI's `Canvas` / `GraphicsContext`.
enum AnnotationRenderer {

    // MARK: - Shadow Parameters

    private static let shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.25)
    private static let shadowOffset = CGSize(width: 0, height: 2)
    private static let shadowBlur: CGFloat = 4

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
        baseImage: CGImage? = nil,
        canvasSize: CGSize? = nil
    ) {
        let color = annotation.color.cgColor
        let lineWidth = annotation.strokeWidth

        ctx.saveGState()

        switch annotation.type {
        case .arrow:
            ctx.setShadow(offset: shadowOffset, blur: shadowBlur, color: shadowColor)
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
            ctx.setShadow(offset: shadowOffset, blur: shadowBlur, color: shadowColor)
            drawText(annotation, in: ctx)

        case .handwriting:
            ctx.setShadow(offset: shadowOffset, blur: shadowBlur, color: shadowColor)
            drawHandwriting(annotation, in: ctx)

        case .counter:
            ctx.setShadow(offset: shadowOffset, blur: shadowBlur, color: shadowColor)
            drawCounter(annotation, in: ctx)

        case .pixelate:
            drawPixelate(annotation, in: ctx, baseImage: baseImage, canvasSize: canvasSize)

        case .blur:
            drawBlur(annotation, in: ctx, baseImage: baseImage, canvasSize: canvasSize)

        case .spotlight:
            drawSpotlight(annotation, in: ctx, baseImage: baseImage, canvasSize: canvasSize)
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
        let bezierCP: CGPoint?
        if let passThrough = annotation.curveControlPoint {
            let cp = bezierControl(from: passThrough, start: start, end: end)
            ctx.addQuadCurve(to: end, control: cp)
            bezierCP = cp
        } else {
            ctx.addLine(to: end)
            bezierCP = nil
        }
        ctx.strokePath()

        // Arrowhead — compute angle from tangent direction at endpoint.
        let angle: CGFloat
        if let cp = bezierCP {
            angle = atan2(end.y - cp.y, end.x - cp.x)
        } else {
            angle = atan2(end.y - start.y, end.x - start.x)
        }
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
        let segments = PathSmoothing.catmullRomSegments(pts)
        for seg in segments {
            ctx.addCurve(to: seg.p1, control1: seg.cp1, control2: seg.cp2)
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

    // MARK: - Handwriting

    private static func drawHandwriting(
        _ annotation: AnnotationDocument.Annotation,
        in ctx: CGContext
    ) {
        guard let string = annotation.text, !string.isEmpty else { return }

        let fontSize = annotation.fontSize ?? 24
        let font = CTFontCreateWithName("Bradley Hand" as CFString, fontSize, nil)
        let color = annotation.color.nsColor

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]

        let attributedString = NSAttributedString(string: string, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)

        ctx.saveGState()
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
        baseImage: CGImage?,
        canvasSize: CGSize?
    ) {
        let rect = rectFromPoints(annotation.startPoint, annotation.endPoint)
        guard let base = baseImage, let cs = canvasSize else {
            drawDashedRect(rect, in: ctx, label: "Pixelate")
            return
        }

        let pixelRect = pointRectToPixelRect(rect, imageSize: base, canvasSize: cs)
        if let filtered = ImageFilters.pixelate(image: base, region: pixelRect) {
            ctx.draw(filtered, in: CGRect(origin: .zero, size: cs))
        }
    }

    private static func drawBlur(
        _ annotation: AnnotationDocument.Annotation,
        in ctx: CGContext,
        baseImage: CGImage?,
        canvasSize: CGSize?
    ) {
        let rect = rectFromPoints(annotation.startPoint, annotation.endPoint)
        guard let base = baseImage, let cs = canvasSize else {
            drawDashedRect(rect, in: ctx, label: "Blur")
            return
        }

        let pixelRect = pointRectToPixelRect(rect, imageSize: base, canvasSize: cs)
        if let filtered = ImageFilters.blur(image: base, region: pixelRect) {
            ctx.draw(filtered, in: CGRect(origin: .zero, size: cs))
        }
    }

    private static func drawSpotlight(
        _ annotation: AnnotationDocument.Annotation,
        in ctx: CGContext,
        baseImage: CGImage?,
        canvasSize: CGSize?
    ) {
        let rect = rectFromPoints(annotation.startPoint, annotation.endPoint)
        guard let base = baseImage, let cs = canvasSize else {
            drawDashedRect(rect, in: ctx, label: "Spotlight")
            return
        }

        let pixelRect = pointRectToPixelRect(rect, imageSize: base, canvasSize: cs)
        if let filtered = ImageFilters.spotlight(image: base, region: pixelRect) {
            ctx.draw(filtered, in: CGRect(origin: .zero, size: cs))
        }
    }

    /// Converts a rect from point coordinates (top-left origin) to pixel
    /// coordinates (bottom-left origin) for CIFilter / CGImage operations.
    private static func pointRectToPixelRect(
        _ rect: CGRect,
        imageSize: CGImage,
        canvasSize: CGSize
    ) -> CGRect {
        let scaleX = CGFloat(imageSize.width) / canvasSize.width
        let scaleY = CGFloat(imageSize.height) / canvasSize.height
        return CGRect(
            x: rect.origin.x * scaleX,
            y: (canvasSize.height - rect.origin.y - rect.height) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
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

    /// Computes the actual quadratic bezier control point from a pass-through point.
    ///
    /// The stored `curveControlPoint` represents where the curve passes through at t=0.5.
    /// A quadratic bezier at t=0.5 is `0.25*P0 + 0.5*P1 + 0.25*P2`, so solving for P1:
    /// `P1 = 2*passThrough - 0.5*start - 0.5*end`.
    static func bezierControl(from passThrough: CGPoint, start: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(
            x: 2 * passThrough.x - 0.5 * start.x - 0.5 * end.x,
            y: 2 * passThrough.y - 0.5 * start.y - 0.5 * end.y
        )
    }

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
