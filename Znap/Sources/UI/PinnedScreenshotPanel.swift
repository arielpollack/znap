import AppKit

/// A borderless floating panel that pins a screenshot on top of all windows.
///
/// Pinned screenshots can be moved freely, resized, and their opacity adjusted
/// via scroll wheel. A right-click context menu provides actions like copy, save,
/// annotate, lock/unlock, and close.
///
/// ## Usage
///
/// ```swift
/// let panel = PinnedScreenshotPanel(image: myNSImage)
/// panel.makeKeyAndOrderFront(nil)
/// ```
///
/// Use ``toggleAllVisibility()`` to hide/show all pinned screenshots at once,
/// or ``closeAll()`` to dismiss them all.
final class PinnedScreenshotPanel: NSPanel {

    // MARK: - Static State

    /// All currently active pinned screenshot panels.
    private static var allPins: [PinnedScreenshotPanel] = []

    // MARK: - Instance Properties

    /// The pinned screenshot image.
    let pinnedImage: NSImage

    /// Whether the pin is locked (clicks pass through to windows behind).
    private var isLocked = false

    // MARK: - Initialization

    /// Creates a new pinned screenshot panel displaying the given image.
    ///
    /// The panel is borderless, floating, always on top, and movable by background.
    /// Initial size is capped at 400 points wide with proportional height.
    ///
    /// - Parameter image: The screenshot to pin.
    init(image: NSImage) {
        self.pinnedImage = image

        // Calculate panel size: max width 400, proportional height
        let maxWidth: CGFloat = 400
        let imageWidth = image.size.width
        let imageHeight = image.size.height
        let scale = imageWidth > maxWidth ? maxWidth / imageWidth : 1.0
        let panelWidth = imageWidth * scale
        let panelHeight = imageHeight * scale

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let originX = screenFrame.midX - panelWidth / 2
        let originY = screenFrame.midY - panelHeight / 2

        super.init(
            contentRect: NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .transient]
        animationBehavior = .utilityWindow
        minSize = NSSize(width: 50, height: 50)

        // Set up the image view as content
        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        contentView = imageView

        // Track this panel
        Self.allPins.append(self)

        makeKeyAndOrderFront(nil)
    }

    // MARK: - Key Window

    override var canBecomeKey: Bool { true }

    // MARK: - Scroll Wheel (Opacity Control)

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY * 0.05
        alphaValue = max(0.1, min(1.0, alphaValue + delta))
    }

    // MARK: - Context Menu

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        menu.addItem(
            withTitle: "Copy",
            action: #selector(copyImage),
            keyEquivalent: ""
        ).target = self

        menu.addItem(
            withTitle: "Save...",
            action: #selector(saveImage),
            keyEquivalent: ""
        ).target = self

        menu.addItem(
            withTitle: "Open in Annotate",
            action: #selector(openAnnotate),
            keyEquivalent: ""
        ).target = self

        menu.addItem(.separator())

        let lockItem = menu.addItem(
            withTitle: isLocked ? "Unlock" : "Lock",
            action: #selector(toggleLock),
            keyEquivalent: ""
        )
        lockItem.target = self

        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Close",
            action: #selector(closePin),
            keyEquivalent: ""
        ).target = self

        NSMenu.popUpContextMenu(menu, with: event, for: contentView!)
    }

    // MARK: - Actions

    /// Copies the pinned image to the system pasteboard.
    @objc func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([pinnedImage])
    }

    /// Presents a save panel to save the pinned image as PNG.
    @objc func saveImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Znap-Pin.png"

        savePanel.begin { [weak self] response in
            guard response == .OK,
                  let url = savePanel.url,
                  let self = self else { return }

            guard let tiffData = self.pinnedImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                return
            }

            try? pngData.write(to: url, options: .atomic)
        }
    }

    /// Opens the pinned image in the annotation editor and closes this pin.
    @objc func openAnnotate() {
        AnnotationEditorWindow.open(with: pinnedImage)
        closePin()
    }

    /// Toggles the lock state. When locked, mouse events pass through to windows behind.
    @objc func toggleLock() {
        isLocked.toggle()
        ignoresMouseEvents = isLocked
    }

    /// Closes this pinned screenshot panel and removes it from the tracking list.
    @objc func closePin() {
        Self.allPins.removeAll { $0 === self }
        orderOut(nil)
    }

    // MARK: - Static Methods

    /// Toggles visibility of all pinned screenshot panels.
    static func toggleAllVisibility() {
        for pin in allPins {
            if pin.isVisible {
                pin.orderOut(nil)
            } else {
                pin.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Closes all pinned screenshot panels.
    static func closeAll() {
        let pins = allPins
        allPins.removeAll()
        for pin in pins {
            pin.orderOut(nil)
        }
    }
}
