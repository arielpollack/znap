import AppKit

/// Provides hit testing for annotations and arrow handles.
enum AnnotationHitTesting {

    /// Returns the ID of the topmost annotation at `point`, or nil.
    /// Iterates in reverse order (last drawn = topmost = first hit).
    static func findTopmost(at point: CGPoint, in annotations: [AnnotationDocument.Annotation]) -> UUID? {
        for annotation in annotations.reversed() {
            if hitTest(point: point, annotation: annotation) {
                return annotation.id
            }
        }
        return nil
    }

    /// Tests whether `point` lies within the interactive region of `annotation`.
    static func hitTest(point: CGPoint, annotation: AnnotationDocument.Annotation, tolerance: CGFloat = 8) -> Bool {
        switch annotation.type {
        case .arrow:
            let effectiveTolerance = tolerance + annotation.strokeWidth / 2
            if let cp = annotation.curveControlPoint {
                return pointToQuadBezierDistance(point, from: annotation.startPoint, control: cp, to: annotation.endPoint) <= effectiveTolerance
            }
            return pointToSegmentDistance(point, from: annotation.startPoint, to: annotation.endPoint) <= effectiveTolerance

        case .line:
            let effectiveTolerance = tolerance + annotation.strokeWidth / 2
            return pointToSegmentDistance(point, from: annotation.startPoint, to: annotation.endPoint) <= effectiveTolerance

        case .rectangle, .ellipse:
            let rect = AnnotationRenderer.rectFromPoints(annotation.startPoint, annotation.endPoint)
            let outer = rect.insetBy(dx: -(tolerance + annotation.strokeWidth / 2),
                                     dy: -(tolerance + annotation.strokeWidth / 2))
            let inner = rect.insetBy(dx: tolerance + annotation.strokeWidth / 2,
                                     dy: tolerance + annotation.strokeWidth / 2)
            if annotation.type == .ellipse {
                let outerPath = CGPath(ellipseIn: outer, transform: nil)
                let innerPath = CGPath(ellipseIn: inner, transform: nil)
                return outerPath.contains(point) && (inner.width <= 0 || inner.height <= 0 || !innerPath.contains(point))
            }
            return outer.contains(point) && (inner.width <= 0 || inner.height <= 0 || !inner.contains(point))

        case .filledRectangle:
            let rect = AnnotationRenderer.rectFromPoints(annotation.startPoint, annotation.endPoint)
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)

        case .text, .handwriting:
            let bounds = textBounds(for: annotation)
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)

        case .counter:
            let dx = point.x - annotation.startPoint.x
            let dy = point.y - annotation.startPoint.y
            return sqrt(dx * dx + dy * dy) <= 14 + tolerance

        case .pencil, .highlighter:
            guard let pts = annotation.points, pts.count >= 2 else { return false }
            let widthMultiplier: CGFloat = annotation.type == .highlighter ? 4 : 1
            let effectiveTolerance = tolerance + (annotation.strokeWidth * widthMultiplier) / 2
            for i in 1..<pts.count {
                if pointToSegmentDistance(point, from: pts[i - 1], to: pts[i]) <= effectiveTolerance {
                    return true
                }
            }
            return false

        case .pixelate, .blur, .spotlight:
            let rect = AnnotationRenderer.rectFromPoints(annotation.startPoint, annotation.endPoint)
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    // MARK: - Arrow Handles

    enum ArrowHandle { case start, end, curve }

    /// Returns which arrow handle (if any) is at `point` when the arrow is selected.
    static func hitTestArrowHandle(
        point: CGPoint, annotation: AnnotationDocument.Annotation, tolerance: CGFloat = 12
    ) -> ArrowHandle? {
        let ds = hypot(point.x - annotation.startPoint.x, point.y - annotation.startPoint.y)
        if ds <= tolerance { return .start }

        let de = hypot(point.x - annotation.endPoint.x, point.y - annotation.endPoint.y)
        if de <= tolerance { return .end }

        // Curve handle: either existing control point or ghost at midpoint.
        let curvePoint = annotation.curveControlPoint ?? CGPoint(
            x: (annotation.startPoint.x + annotation.endPoint.x) / 2,
            y: (annotation.startPoint.y + annotation.endPoint.y) / 2
        )
        let dc = hypot(point.x - curvePoint.x, point.y - curvePoint.y)
        if dc <= tolerance { return .curve }

        return nil
    }

    // MARK: - Bounding Box

    /// Returns the bounding box for an annotation, used for selection indicators.
    static func boundingBox(for annotation: AnnotationDocument.Annotation) -> CGRect {
        switch annotation.type {
        case .arrow, .line:
            let rect = AnnotationRenderer.rectFromPoints(annotation.startPoint, annotation.endPoint)
            let expansion = annotation.strokeWidth + 4
            var result = rect.insetBy(dx: -expansion, dy: -expansion)
            if let cp = annotation.curveControlPoint {
                result = result.union(CGRect(x: cp.x - expansion, y: cp.y - expansion,
                                             width: expansion * 2, height: expansion * 2))
            }
            return result

        case .rectangle, .ellipse, .filledRectangle, .pixelate, .blur, .spotlight:
            let rect = AnnotationRenderer.rectFromPoints(annotation.startPoint, annotation.endPoint)
            return rect.insetBy(dx: -4, dy: -4)

        case .text, .handwriting:
            return textBounds(for: annotation).insetBy(dx: -4, dy: -4)

        case .counter:
            let r: CGFloat = 14 + 4
            return CGRect(x: annotation.startPoint.x - r, y: annotation.startPoint.y - r,
                         width: r * 2, height: r * 2)

        case .pencil, .highlighter:
            guard let pts = annotation.points, !pts.isEmpty else {
                return CGRect(origin: annotation.startPoint, size: .zero)
            }
            var minX = pts[0].x, maxX = pts[0].x
            var minY = pts[0].y, maxY = pts[0].y
            for p in pts.dropFirst() {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            let widthMultiplier: CGFloat = annotation.type == .highlighter ? 4 : 1
            let expansion = annotation.strokeWidth * widthMultiplier / 2 + 4
            return CGRect(x: minX - expansion, y: minY - expansion,
                         width: maxX - minX + expansion * 2,
                         height: maxY - minY + expansion * 2)
        }
    }

    // MARK: - Resize Handles

    enum ResizeHandle { case bottomRight }

    /// Returns which resize handle (if any) is at `point` when a text/handwriting annotation is selected.
    static func hitTestResizeHandle(
        point: CGPoint, annotation: AnnotationDocument.Annotation, tolerance: CGFloat = 12
    ) -> ResizeHandle? {
        guard annotation.type == .text || annotation.type == .handwriting else { return nil }
        let bounds = textBounds(for: annotation)
        let br = CGPoint(x: bounds.maxX, y: bounds.maxY)
        if hypot(point.x - br.x, point.y - br.y) <= tolerance { return .bottomRight }
        return nil
    }

    // MARK: - Text Bounds

    /// Approximate text bounds based on font and string.
    static func textBounds(for annotation: AnnotationDocument.Annotation) -> CGRect {
        guard let string = annotation.text, !string.isEmpty else {
            return CGRect(origin: annotation.startPoint, size: .zero)
        }
        let fontSize = annotation.fontSize ?? 16
        let fontName: String = annotation.type == .handwriting ? "Bradley Hand" : "Helvetica"
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (string as NSString).size(withAttributes: attributes)
        return CGRect(origin: annotation.startPoint, size: size)
    }

    /// Distance from a point to a line segment.
    private static func pointToSegmentDistance(_ p: CGPoint, from a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return hypot(p.x - projX, p.y - projY)
    }

    /// Approximate distance from a point to a quadratic bezier curve.
    private static func pointToQuadBezierDistance(_ p: CGPoint, from a: CGPoint, control c: CGPoint, to b: CGPoint) -> CGFloat {
        // Sample the curve at intervals and find minimum distance.
        let segments = 20
        var minDist = CGFloat.greatestFiniteMagnitude
        var prev = a
        for i in 1...segments {
            let t = CGFloat(i) / CGFloat(segments)
            let oneMinusT = 1 - t
            let pt = CGPoint(
                x: oneMinusT * oneMinusT * a.x + 2 * oneMinusT * t * c.x + t * t * b.x,
                y: oneMinusT * oneMinusT * a.y + 2 * oneMinusT * t * c.y + t * t * b.y
            )
            let d = pointToSegmentDistance(p, from: prev, to: pt)
            minDist = min(minDist, d)
            prev = pt
        }
        return minDist
    }
}
