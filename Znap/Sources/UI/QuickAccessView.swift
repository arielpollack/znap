import AppKit

/// The content view for ``QuickAccessOverlay``, displaying a thumbnail preview
/// of the captured image alongside dimension text and keyboard-shortcut hints.
///
/// Supports:
/// - **Cmd+C** — copy to clipboard
/// - **Cmd+S** — save to Desktop
/// - **Cmd+W / Esc** — dismiss
/// - **Click** — open annotation editor
/// - **Drag** — initiate a drag session (drag the image to other apps)
final class QuickAccessView: NSView, NSDraggingSource {

    // MARK: - Subviews

    private let thumbnailView = NSImageView()
    private let dimensionLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    // MARK: - Properties

    /// Callback invoked when the user triggers an action.
    var onAction: ((QuickAccessOverlay.Action) -> Void)?

    /// The image being displayed, retained for drag operations.
    private var image: NSImage?

    /// The point where a mouse-down began, used to distinguish click from drag.
    private var mouseDownPoint: NSPoint?

    // MARK: - Configuration

    /// Configures the view with the captured image, setting up the thumbnail
    /// and dimension label.
    ///
    /// - Parameter image: The captured screenshot.
    func configure(image: NSImage) {
        self.image = image
        thumbnailView.image = image

        let w = Int(image.size.width)
        let h = Int(image.size.height)
        dimensionLabel.stringValue = "\(w) \u{00D7} \(h)"
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true
        guard let layer = self.layer else { return }

        layer.cornerRadius = 10
        layer.masksToBounds = true
        layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer.borderWidth = 0.5
        layer.borderColor = NSColor.separatorColor.cgColor

        // Thumbnail — left side, 64x64.
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.masksToBounds = true
        addSubview(thumbnailView)

        // Dimension label — top right, monospaced.
        dimensionLabel.translatesAutoresizingMaskIntoConstraints = false
        dimensionLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        dimensionLabel.textColor = .labelColor
        dimensionLabel.lineBreakMode = .byTruncatingTail
        addSubview(dimensionLabel)

        // Hint label — bottom right, small.
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.stringValue = "\u{2318}C copy  \u{2318}S save  Click annotate"
        hintLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            // Thumbnail: left-aligned, vertically centered, 64x64.
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 64),
            thumbnailView.heightAnchor.constraint(equalToConstant: 64),

            // Dimension label: to the right of thumbnail, near the top.
            dimensionLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10),
            dimensionLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            dimensionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),

            // Hint label: to the right of thumbnail, near the bottom.
            hintLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 10),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    // MARK: - Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool { true }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCmd = flags.contains(.command)

        switch event.keyCode {
        case 8 where hasCmd:   // Cmd+C
            onAction?(.copyToClipboard)
        case 1 where hasCmd:   // Cmd+S
            onAction?(.save)
        case 13 where hasCmd:  // Cmd+W
            onAction?(.dismiss)
        case 53:               // Escape
            onAction?(.dismiss)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = mouseDownPoint,
              let image = image else { return }

        let currentPoint = convert(event.locationInWindow, from: nil)
        let dx = currentPoint.x - startPoint.x
        let dy = currentPoint.y - startPoint.y

        // Only start a drag if the mouse has moved more than 3 points.
        guard sqrt(dx * dx + dy * dy) > 3 else { return }

        // Clear the mouse-down point so we don't fire openAnnotate on mouseUp.
        mouseDownPoint = nil

        let draggingItem = NSDraggingItem(pasteboardWriter: image)
        draggingItem.setDraggingFrame(
            NSRect(origin: startPoint, size: NSSize(width: 64, height: 64)),
            contents: image
        )

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        // If mouseDownPoint is still set, the user clicked without dragging.
        guard mouseDownPoint != nil else { return }
        mouseDownPoint = nil
        onAction?(.openAnnotate)
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}
