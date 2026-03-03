import AppKit

/// Renders a screenshot on top of a styled background with configurable padding,
/// corner radius, shadow, and aspect ratio.
///
/// The renderer supports gradient presets and solid colour backgrounds. The output
/// is a new ``NSImage`` containing the composited result.
///
/// ## Usage
///
/// ```swift
/// var config = BackgroundRenderer.Config()
/// config.backgroundType = .gradient(preset: 0)
/// config.padding = 40
/// config.cornerRadius = 10
/// if let result = BackgroundRenderer.render(screenshot: myImage, config: config) {
///     // use result
/// }
/// ```
enum BackgroundRenderer {

    // MARK: - Config

    /// Configuration controlling how the background is rendered.
    struct Config {
        /// The type of background to draw behind the screenshot.
        var backgroundType: BackgroundType = .gradient(preset: 0)
        /// Padding in points around the screenshot.
        var padding: CGFloat = 40
        /// Corner radius applied to the screenshot.
        var cornerRadius: CGFloat = 10
        /// Whether a drop shadow is drawn behind the screenshot.
        var addShadow: Bool = true
        /// Optional aspect ratio constraint for the canvas.
        var aspectRatio: AspectRatio? = nil
    }

    // MARK: - BackgroundType

    /// The kind of background drawn behind the screenshot.
    enum BackgroundType {
        /// A gradient selected from ``gradientPresets`` by index.
        case gradient(preset: Int)
        /// A solid colour fill.
        case solid(NSColor)
    }

    // MARK: - AspectRatio

    /// Supported canvas aspect ratios.
    enum AspectRatio: String, CaseIterable {
        case free
        case square
        case fourThree
        case sixteenNine
        case nineSixteen

        /// The numeric ratio value, or `nil` for free-form.
        var value: CGFloat? {
            switch self {
            case .free: return nil
            case .square: return 1.0
            case .fourThree: return 4.0 / 3.0
            case .sixteenNine: return 16.0 / 9.0
            case .nineSixteen: return 9.0 / 16.0
            }
        }

        /// Human-readable label.
        var label: String {
            switch self {
            case .free: return "Free"
            case .square: return "1:1"
            case .fourThree: return "4:3"
            case .sixteenNine: return "16:9"
            case .nineSixteen: return "9:16"
            }
        }
    }

    // MARK: - Gradient Presets

    /// Ten gradient colour pairs used as background presets.
    static let gradientPresets: [(NSColor, NSColor)] = [
        (.systemBlue, .systemPurple),
        (.systemPink, .systemOrange),
        (.systemGreen, .systemTeal),
        (.systemIndigo, .systemBlue),
        (.systemOrange, .systemYellow),
        (.systemPurple, .systemPink),
        (.systemTeal, .systemGreen),
        (.systemRed, .systemOrange),
        (.systemYellow, .systemGreen),
        (.systemBlue, .systemTeal),
    ]

    // MARK: - Render

    /// Renders the screenshot onto a styled background.
    ///
    /// - Parameters:
    ///   - screenshot: The source screenshot image.
    ///   - config: Rendering configuration (background, padding, corners, shadow, aspect ratio).
    /// - Returns: A new composited image, or `nil` if rendering fails.
    static func render(screenshot: NSImage, config: Config) -> NSImage? {
        let imgWidth = screenshot.size.width
        let imgHeight = screenshot.size.height

        // Calculate canvas size
        var canvasWidth = imgWidth + config.padding * 2
        var canvasHeight = imgHeight + config.padding * 2

        // Apply aspect ratio constraint
        if let ratio = config.aspectRatio?.value {
            let currentRatio = canvasWidth / canvasHeight
            if currentRatio > ratio {
                // Canvas is too wide; increase height
                canvasHeight = canvasWidth / ratio
            } else {
                // Canvas is too tall; increase width
                canvasWidth = canvasHeight * ratio
            }
        }

        let canvasSize = NSSize(width: canvasWidth, height: canvasHeight)
        let result = NSImage(size: canvasSize)

        result.lockFocus()
        defer { result.unlockFocus() }

        let canvasRect = NSRect(origin: .zero, size: canvasSize)

        // Draw background
        switch config.backgroundType {
        case .gradient(let preset):
            let index = max(0, min(preset, gradientPresets.count - 1))
            let (startColor, endColor) = gradientPresets[index]
            if let gradient = NSGradient(starting: startColor, ending: endColor) {
                gradient.draw(in: canvasRect, angle: 135)
            }

        case .solid(let color):
            color.setFill()
            canvasRect.fill()
        }

        // Calculate centered image rect
        let imageRect = NSRect(
            x: (canvasWidth - imgWidth) / 2,
            y: (canvasHeight - imgHeight) / 2,
            width: imgWidth,
            height: imgHeight
        )

        // Draw shadow if enabled
        if config.addShadow {
            let context = NSGraphicsContext.current!
            context.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.shadowOffset = NSSize(width: 0, height: -4)
            shadow.shadowBlurRadius = 20
            shadow.set()

            // Draw a filled rect so the shadow is visible
            let shadowPath = NSBezierPath(roundedRect: imageRect, xRadius: config.cornerRadius, yRadius: config.cornerRadius)
            NSColor.white.setFill()
            shadowPath.fill()
            context.restoreGraphicsState()
        }

        // Draw screenshot with rounded corners
        let clipPath = NSBezierPath(roundedRect: imageRect, xRadius: config.cornerRadius, yRadius: config.cornerRadius)
        clipPath.addClip()
        screenshot.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        return result
    }
}
