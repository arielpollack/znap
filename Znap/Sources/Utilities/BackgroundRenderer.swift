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
    /// Codable for persistence via UserDefaults. Equatable for SwiftUI onChange.
    struct Config: Codable, Equatable {
        /// Whether the background is enabled.
        var enabled: Bool = false
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
        /// Whether to show a dummy macOS window header bar.
        var showWindowHeader: Bool = false
        /// The title displayed in the window header bar.
        var windowTitle: String = ""

        enum CodingKeys: String, CodingKey {
            case enabled, backgroundType, padding, cornerRadius, addShadow, aspectRatio, showWindowHeader
        }

        // MARK: - Persistence

        private static let userDefaultsKey = "backgroundConfig"

        /// Loads the saved config from UserDefaults, or returns defaults.
        static func load() -> Config {
            guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
                  let config = try? JSONDecoder().decode(Config.self, from: data) else {
                return Config()
            }
            return config
        }

        /// Saves the config to UserDefaults.
        func save() {
            guard let data = try? JSONEncoder().encode(self) else { return }
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    // MARK: - BackgroundType

    /// The kind of background drawn behind the screenshot.
    enum BackgroundType: Codable, Equatable {
        /// A gradient selected from ``gradientPresets`` by index.
        case gradient(preset: Int)
        /// A solid colour fill, stored as RGBA components.
        case solid(CodableColor)
    }

    /// A Codable colour representation for solid backgrounds.
    struct CodableColor: Codable, Equatable {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var alpha: CGFloat

        var nsColor: NSColor {
            NSColor(red: red, green: green, blue: blue, alpha: alpha)
        }

        init(_ color: NSColor) {
            let c = color.usingColorSpace(.sRGB) ?? color
            self.red = c.redComponent
            self.green = c.greenComponent
            self.blue = c.blueComponent
            self.alpha = c.alphaComponent
        }
    }

    // MARK: - AspectRatio

    /// Supported canvas aspect ratios.
    enum AspectRatio: String, CaseIterable, Codable {
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

    // MARK: - Window Header Constants

    /// Height of the dummy macOS window header bar in points.
    static let headerHeight: CGFloat = 28
    /// Diameter of each traffic light circle.
    private static let trafficLightSize: CGFloat = 12
    /// Left inset for the first traffic light circle center.
    private static let trafficLightInset: CGFloat = 14
    /// Spacing between traffic light circle centers.
    private static let trafficLightSpacing: CGFloat = 20
    /// Traffic light colors: close (red), minimize (yellow), zoom (green).
    private static let trafficLightColors: [NSColor] = [
        NSColor(red: 1.0, green: 0.373, blue: 0.341, alpha: 1),   // #FF5F57
        NSColor(red: 0.996, green: 0.737, blue: 0.180, alpha: 1),  // #FEBC2E
        NSColor(red: 0.157, green: 0.784, blue: 0.251, alpha: 1),  // #28C840
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
        let headerH = config.showWindowHeader ? headerHeight : 0

        // Calculate canvas size (image + header + padding)
        var canvasWidth = imgWidth + config.padding * 2
        var canvasHeight = imgHeight + headerH + config.padding * 2

        // Apply aspect ratio constraint
        if let ratio = config.aspectRatio?.value {
            let currentRatio = canvasWidth / canvasHeight
            if currentRatio > ratio {
                canvasHeight = canvasWidth / ratio
            } else {
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
        case .solid(let codableColor):
            codableColor.nsColor.setFill()
            canvasRect.fill()
        }

        // Calculate centered image rect (shifted down by header height)
        let contentHeight = imgHeight + headerH
        let imageRect = NSRect(
            x: (canvasWidth - imgWidth) / 2,
            y: (canvasHeight - contentHeight) / 2,
            width: imgWidth,
            height: imgHeight
        )

        // The combined rect encompasses both image and header
        let contentRect = NSRect(
            x: imageRect.minX,
            y: imageRect.minY,
            width: imgWidth,
            height: contentHeight
        )

        // Draw shadow if enabled (around the combined content rect)
        if config.addShadow {
            let context = NSGraphicsContext.current!
            context.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.shadowOffset = NSSize(width: 0, height: -4)
            shadow.shadowBlurRadius = 20
            shadow.set()

            let shadowPath = NSBezierPath(roundedRect: contentRect, xRadius: config.cornerRadius, yRadius: config.cornerRadius)
            NSColor.white.setFill()
            shadowPath.fill()
            context.restoreGraphicsState()
        }

        // Clip to the combined content rect with rounded corners
        let context = NSGraphicsContext.current!
        context.saveGraphicsState()
        let clipPath = NSBezierPath(roundedRect: contentRect, xRadius: config.cornerRadius, yRadius: config.cornerRadius)
        clipPath.addClip()

        // Draw screenshot in the image rect
        screenshot.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        // Draw window header if enabled
        if config.showWindowHeader {
            let headerRect = NSRect(
                x: imageRect.minX,
                y: imageRect.maxY,
                width: imgWidth,
                height: headerH
            )

            // Header background
            NSColor(red: 0.91, green: 0.91, blue: 0.91, alpha: 1).setFill()
            headerRect.fill()

            // Traffic lights
            let circleY = headerRect.midY
            for (i, color) in trafficLightColors.enumerated() {
                let cx = headerRect.minX + trafficLightInset + CGFloat(i) * trafficLightSpacing
                let circleRect = NSRect(
                    x: cx - trafficLightSize / 2,
                    y: circleY - trafficLightSize / 2,
                    width: trafficLightSize,
                    height: trafficLightSize
                )
                color.setFill()
                NSBezierPath(ovalIn: circleRect).fill()
            }

            // Title text centered in header
            if !config.windowTitle.isEmpty {
                let font = NSFont.systemFont(ofSize: 13, weight: .regular)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
                let titleStr = config.windowTitle as NSString
                let titleSize = titleStr.size(withAttributes: attributes)
                let titleX = headerRect.midX - titleSize.width / 2
                let titleY = headerRect.midY - titleSize.height / 2
                titleStr.draw(at: NSPoint(x: titleX, y: titleY), withAttributes: attributes)
            }
        }

        context.restoreGraphicsState()

        return result
    }
}
