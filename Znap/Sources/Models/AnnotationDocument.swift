import AppKit

/// The persistence model for an annotated screenshot.
///
/// ``AnnotationDocument`` stores the base image data (PNG), a canvas size, and
/// an ordered array of annotations. The struct is fully `Codable`, making it
/// straightforward to serialize to disk or paste into a clipboard payload.
struct AnnotationDocument: Codable {

    // MARK: - Stored Properties

    /// PNG data for the base screenshot.
    var imageData: Data

    /// All annotations layered on top of the base image, in draw order.
    var annotations: [Annotation] = []

    /// The size of the canvas (matches the base image dimensions).
    var canvasSize: CGSize

    // MARK: - AnnotationType

    /// Every visual mark the user can place on the canvas.
    enum AnnotationType: String, Codable, CaseIterable {
        case arrow, rectangle, filledRectangle, ellipse, line
        case text, counter, pixelate, blur, spotlight
        case highlighter, pencil
        case handwriting
    }

    // MARK: - Annotation

    /// A single annotation drawn on the canvas.
    struct Annotation: Codable, Identifiable {
        let id: UUID
        var type: AnnotationType
        var startPoint: CGPoint
        var endPoint: CGPoint
        /// Freehand path points (used by pencil/highlighter).
        var points: [CGPoint]?
        var color: CodableColor
        var strokeWidth: CGFloat
        var text: String?
        var fontSize: CGFloat?
        var counterValue: Int?
        var isFilled: Bool
        var curveControlPoint: CGPoint?
    }

    // MARK: - CodableColor

    /// A simple, `Codable`-friendly color representation.
    struct CodableColor: Codable, Equatable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        /// The default annotation color — a vivid red.
        static let defaultRed = CodableColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)

        /// Converts to an `NSColor`.
        var nsColor: NSColor {
            NSColor(red: red, green: green, blue: blue, alpha: alpha)
        }

        /// Converts to a `CGColor`.
        var cgColor: CGColor {
            CGColor(red: red, green: green, blue: blue, alpha: alpha)
        }

        /// Creates a ``CodableColor`` from an `NSColor`.
        ///
        /// Falls back to ``defaultRed`` when the colour space conversion fails.
        static func from(nsColor: NSColor) -> CodableColor {
            guard let c = nsColor.usingColorSpace(.sRGB) else { return .defaultRed }
            return CodableColor(
                red: c.redComponent,
                green: c.greenComponent,
                blue: c.blueComponent,
                alpha: c.alphaComponent
            )
        }
    }
}

