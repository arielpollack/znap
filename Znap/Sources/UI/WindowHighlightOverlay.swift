import AppKit
import Carbon

/// A full-screen transparent panel that highlights the window under the cursor
/// and captures it on click.
///
/// When active, this overlay:
/// 1. Tracks the mouse cursor across all screens.
/// 2. Highlights the window beneath the cursor with a blue tint overlay.
/// 3. On click, captures the highlighted window via its `CGWindowID`.
/// 4. On Escape, cancels the selection.
///
/// ## Usage
///
/// ```swift
/// WindowHighlightOverlay.beginWindowSelection { windowID in
///     guard let windowID else { return }  // user cancelled
///     // Use CaptureService.shared.captureWindow(windowID)
/// }
/// ```
final class WindowHighlightOverlay {

    // MARK: - Static State

    /// The currently active overlay panel (one per session).
    private static var activePanel: NSPanel?

    /// The blue highlight window shown over the hovered window.
    private static var highlightWindow: NSWindow?

    // MARK: - Static Entry Point

    /// Begins an interactive window-selection session.
    ///
    /// Creates a full-screen transparent panel that tracks the mouse cursor,
    /// highlights the window under the cursor, and waits for a click or Escape.
    ///
    /// - Parameter completion: Called with the `CGWindowID` of the selected window,
    ///   or `nil` if the user cancelled.
    static func beginWindowSelection(completion: @escaping (CGWindowID?) -> Void) {
        guard let screen = NSScreen.main else {
            completion(nil)
            return
        }

        // Union of all screen frames for full coverage.
        let fullFrame = NSScreen.screens.reduce(CGRect.zero) { $0.union($1.frame) }

        let panel = NSPanel(
            contentRect: fullFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false

        let trackingView = WindowTrackingView(frame: NSRect(origin: .zero, size: fullFrame.size))
        trackingView.onCapture = { windowID in
            cleanup()
            completion(windowID)
        }
        trackingView.onCancel = {
            cleanup()
            completion(nil)
        }

        panel.contentView = trackingView
        activePanel = panel

        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
    }

    /// Cleans up the overlay panel and highlight window.
    private static func cleanup() {
        NSCursor.pop()
        highlightWindow?.orderOut(nil)
        highlightWindow = nil
        activePanel?.orderOut(nil)
        activePanel = nil
    }

    /// Shows or moves the blue highlight window to the given frame.
    fileprivate static func showHighlight(at frame: NSRect) {
        if highlightWindow == nil {
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
            window.isOpaque = false
            window.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15)
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false

            // Add a border view.
            let borderView = NSView(frame: NSRect(origin: .zero, size: frame.size))
            borderView.wantsLayer = true
            borderView.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
            borderView.layer?.borderWidth = 2
            borderView.autoresizingMask = [.width, .height]
            window.contentView = borderView

            highlightWindow = window
            window.orderFront(nil)
        } else {
            highlightWindow?.setFrame(frame, display: true)
        }
    }

    /// Hides the highlight window.
    fileprivate static func hideHighlight() {
        highlightWindow?.orderOut(nil)
        highlightWindow = nil
    }
}

// MARK: - WindowTrackingView

/// NSView subclass that tracks mouse movement and detects windows under the cursor.
///
/// Uses `CGWindowListCopyWindowInfo` to enumerate on-screen windows, filters out
/// our own process, and finds the first window whose bounds contain the mouse location.
private final class WindowTrackingView: NSView {

    /// Called with the `CGWindowID` when the user clicks on a highlighted window.
    var onCapture: ((CGWindowID) -> Void)?

    /// Called when the user presses Escape to cancel.
    var onCancel: (() -> Void)?

    /// The `CGWindowID` of the window currently under the cursor.
    private var currentWindowID: CGWindowID = 0

    /// Tracking area for receiving `mouseMoved` events.
    private var trackingArea: NSTrackingArea?

    // MARK: - Responder

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Mouse Events

    override func mouseMoved(with event: NSEvent) {
        updateHighlight()
    }

    override func mouseDown(with event: NSEvent) {
        // Ensure we have a valid window under the cursor.
        updateHighlight()
        if currentWindowID != 0 {
            onCapture?(currentWindowID)
        }
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Window Detection

    /// Finds the window under the current mouse location and updates the highlight.
    private func updateHighlight() {
        let mouseLocation = NSEvent.mouseLocation
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // Total screen height for CG-to-NS coordinate conversion.
        let screenHeight = NSScreen.screens.reduce(CGFloat(0)) { result, screen in
            max(result, screen.frame.maxY)
        }

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            WindowHighlightOverlay.hideHighlight()
            currentWindowID = 0
            return
        }

        for entry in windowList {
            // Skip windows belonging to our own process.
            guard let pid = entry[kCGWindowOwnerPID] as? Int32,
                  pid != ownPID else { continue }

            // Skip windows with no bounds.
            guard let boundsDict = entry[kCGWindowBounds] as? [String: CGFloat] else { continue }

            // CGWindowList bounds use top-left origin (CG coordinates).
            guard let cgX = boundsDict["X"],
                  let cgY = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else { continue }

            // Convert CG coordinates (top-left origin) to NS coordinates (bottom-left origin).
            let nsY = screenHeight - cgY - height
            let nsFrame = NSRect(x: cgX, y: nsY, width: width, height: height)

            if nsFrame.contains(mouseLocation) {
                guard let windowID = entry[kCGWindowNumber] as? CGWindowID else { continue }

                // Skip tiny or zero-sized windows (e.g., menu bar extras).
                guard width > 10, height > 10 else { continue }

                currentWindowID = windowID
                WindowHighlightOverlay.showHighlight(at: nsFrame)
                return
            }
        }

        // No window found under cursor.
        WindowHighlightOverlay.hideHighlight()
        currentWindowID = 0
    }
}
