import AppKit

/// A floating panel that appears after every capture, providing quick access to
/// common post-capture actions: copy, save, annotate, pin, or drag.
///
/// Only one ``QuickAccessOverlay`` is active at a time. Calling ``show(image:)``
/// replaces any previous overlay. The overlay auto-dismisses after a configurable
/// timeout (default 15 seconds) and can be dismissed manually with Escape or Cmd+W.
///
/// ## Usage
///
/// ```swift
/// let nsImage = NSImage(cgImage: capturedCGImage, size: NSSize(width: w, height: h))
/// QuickAccessOverlay.show(image: nsImage)
/// ```
final class QuickAccessOverlay: NSPanel {

    // MARK: - Action Enum

    /// Actions the overlay can dispatch in response to user interaction.
    enum Action {
        case openAnnotate
        case copyToClipboard
        case save
        case saveAs
        case pin
        case dismiss
    }

    // MARK: - Static State

    /// The currently visible overlay, if any. Only one overlay is shown at a time.
    private(set) static var current: QuickAccessOverlay?

    // MARK: - Instance Properties

    /// The captured image displayed in this overlay.
    let image: NSImage

    /// Timer that auto-dismisses the overlay after a timeout.
    private var dismissTimer: Timer?

    /// Auto-dismiss interval in seconds. Default is 15 seconds.
    static var dismissInterval: TimeInterval = 15

    // MARK: - Initialization

    /// Creates a new Quick Access Overlay displaying the given image.
    ///
    /// - Parameter image: The captured screenshot to display.
    init(image: NSImage) {
        self.image = image

        // Position in the bottom-right corner of the main screen, 16px margin.
        let panelSize = NSSize(width: 280, height: 80)
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.maxX - panelSize.width - 16,
            y: screenFrame.minY + 16
        )

        super.init(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .transient]
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false

        let contentView = QuickAccessView(frame: NSRect(origin: .zero, size: panelSize))
        contentView.configure(image: image)
        contentView.onAction = { [weak self] action in
            self?.handleAction(action)
        }
        self.contentView = contentView
    }

    // MARK: - Key Window

    override var canBecomeKey: Bool { true }

    // MARK: - Static Methods

    /// Shows a new Quick Access Overlay for the given image.
    ///
    /// Closes any previously visible overlay, creates a new one, makes it key,
    /// and starts the auto-dismiss timer.
    ///
    /// - Parameter image: The captured screenshot to display.
    static func show(image: NSImage) {
        // Close any existing overlay first.
        current?.dismissTimer?.invalidate()
        current?.orderOut(nil)

        let overlay = QuickAccessOverlay(image: image)
        current = overlay

        NSApp.activate(ignoringOtherApps: true)
        overlay.alphaValue = 0
        overlay.makeKeyAndOrderFront(nil)

        // Fade in.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            overlay.animator().alphaValue = 1
        }

        overlay.startDismissTimer()
    }

    /// Restores the current overlay to visibility if one exists.
    ///
    /// Useful when the overlay was temporarily hidden (e.g., during annotation).
    static func restoreLast() {
        guard let overlay = current else { return }
        overlay.alphaValue = 1
        overlay.makeKeyAndOrderFront(nil)
        overlay.startDismissTimer()
    }

    // MARK: - Timer

    /// Starts (or restarts) the auto-dismiss timer.
    private func startDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: Self.dismissInterval,
            repeats: false
        ) { [weak self] _ in
            self?.animateOut()
        }
    }

    // MARK: - Animation

    /// Fades the overlay out over 0.3 seconds, then removes it from screen.
    func animateOut() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            if Self.current === self {
                Self.current = nil
            }
        })
    }

    // MARK: - Action Handling

    /// Dispatches the given action to the appropriate handler.
    ///
    /// - Parameter action: The user-requested action.
    func handleAction(_ action: Action) {
        switch action {
        case .copyToClipboard:
            copyImageToClipboard()
        case .save:
            saveToDesktop()
        case .dismiss:
            animateOut()
        case .openAnnotate:
            AnnotationEditorWindow.open(with: image)
            animateOut()
        case .saveAs:
            // TODO: wire up NSSavePanel
            break
        case .pin:
            let _ = PinnedScreenshotPanel(image: image)
            animateOut()
        }
    }

    // MARK: - Private Action Implementations

    /// Copies the captured image to the system pasteboard.
    private func copyImageToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        animateOut()
    }

    /// Saves the captured image as a PNG file on the user's Desktop
    /// with a timestamp filename: "Znap-yyyy-MM-dd-HHmmss.png".
    private func saveToDesktop() {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "Znap-\(timestamp).png"

        let desktopURL = FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first!

        let fileURL = desktopURL.appendingPathComponent(filename)

        do {
            try pngData.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("QuickAccessOverlay: failed to save screenshot — \(error)")
        }

        animateOut()
    }
}
