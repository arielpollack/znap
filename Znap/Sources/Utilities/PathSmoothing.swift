import Foundation

/// Utilities for simplifying and smoothing freehand-drawn point sequences.
enum PathSmoothing {

    // MARK: - Ramer-Douglas-Peucker Simplification

    /// Reduces the number of points in a polyline while preserving its shape.
    ///
    /// Nearly-straight segments collapse to their endpoints, while intentional
    /// curves retain enough points to stay faithful to the original path.
    ///
    /// - Parameters:
    ///   - points: The original point sequence.
    ///   - epsilon: Maximum perpendicular distance a point can deviate from the
    ///     simplified line before it is kept. Smaller values preserve more detail.
    /// - Returns: A simplified array of points.
    static func simplify(_ points: [CGPoint], epsilon: CGFloat = 8.0) -> [CGPoint] {
        guard points.count > 2 else { return points }
        return rdp(points, epsilon: epsilon)
    }

    private static func rdp(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        let first = points.first!
        let last = points.last!

        var maxDistance: CGFloat = 0
        var maxIndex = 0

        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(points[i], lineStart: first, lineEnd: last)
            if d > maxDistance {
                maxDistance = d
                maxIndex = i
            }
        }

        if maxDistance > epsilon {
            let left = rdp(Array(points[...maxIndex]), epsilon: epsilon)
            let right = rdp(Array(points[maxIndex...]), epsilon: epsilon)
            // Drop the duplicate point at the junction.
            return Array(left.dropLast()) + right
        } else {
            return [first, last]
        }
    }

    private static func perpendicularDistance(
        _ point: CGPoint,
        lineStart: CGPoint,
        lineEnd: CGPoint
    ) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSq = dx * dx + dy * dy

        if lengthSq == 0 {
            return hypot(point.x - lineStart.x, point.y - lineStart.y)
        }

        let num = abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x)
        return num / sqrt(lengthSq)
    }

    // MARK: - Catmull-Rom Spline

    /// Generates cubic Bezier control points for a Catmull-Rom spline that
    /// passes through all given points.
    ///
    /// Each returned segment contains `(p0, cp1, cp2, p1)` — the start point,
    /// two cubic Bezier control points, and the end point.
    ///
    /// - Parameters:
    ///   - points: The points to interpolate (minimum 2).
    ///   - alpha: Tension parameter. 0.5 = centripetal (recommended), 0.0 = uniform.
    /// - Returns: An array of Bezier segment tuples.
    static func catmullRomSegments(
        _ points: [CGPoint],
        alpha: CGFloat = 0.5
    ) -> [(p0: CGPoint, cp1: CGPoint, cp2: CGPoint, p1: CGPoint)] {
        guard points.count >= 2 else { return [] }

        // Pad the sequence: duplicate first and last points so every interior
        // pair has neighbours on both sides.
        let padded = [points[0]] + points + [points[points.count - 1]]

        var segments: [(CGPoint, CGPoint, CGPoint, CGPoint)] = []

        for i in 1..<(padded.count - 2) {
            let p0 = padded[i - 1]
            let p1 = padded[i]
            let p2 = padded[i + 1]
            let p3 = padded[i + 2]

            // Convert Catmull-Rom to cubic Bezier control points.
            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )

            segments.append((p1, cp1, cp2, p2))
        }

        return segments
    }
}
