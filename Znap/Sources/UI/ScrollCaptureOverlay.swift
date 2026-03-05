import AppKit

/// A transparent, mouse-passthrough overlay that shows a blinking red border
/// around the capture area and a "Press ENTER to stop" indicator during
/// manual scrolling capture.
///
/// The overlay uses `ignoresMouseEvents = true` so the user can freely scroll
/// content underneath. Global and local event monitors catch ENTER to finish
/// capturing and ESC to cancel.
///
/// ## Usage
///
/// ```swift
/// ScrollCaptureOverlay.show(around: rect, onStop: { ... }, onCancel: { ... })
/// ScrollCaptureOverlay.dismiss()
/// ```
final class ScrollCaptureOverlay {

    private static var panels: [NSPanel] = []
    private static var blinkTimer: Timer?
    private static var globalMonitor: Any?
    private static var localMonitor: Any?

    /// Shows the overlay on all screens with a blinking red border around `rect`.
    ///
    /// - Parameters:
    ///   - rect: The selected capture area in screen coordinates (AppKit, bottom-left origin).
    ///   - onStop: Called when the user presses ENTER to finish capturing.
    ///   - onCancel: Called when the user presses ESC to cancel.
    /// - Returns: The `CGWindowID` of the topmost overlay panel. Pass this to
    ///   `CGWindowListCreateImage` with `.optionOnScreenBelowWindow` to exclude
    ///   the overlay from screen captures.
    @discardableResult
    static func show(
        around rect: CGRect,
        onStop: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> CGWindowID {
        dismiss()

        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false

            let view = ScrollCaptureOverlayView(
                frame: screen.frame,
                selectionRect: rect
            )
            panel.contentView = view
            panel.orderFrontRegardless()

            panels.append(panel)
        }

        // Blink the border every 0.5s
        var borderVisible = true
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            borderVisible.toggle()
            for panel in panels {
                (panel.contentView as? ScrollCaptureOverlayView)?.borderVisible = borderVisible
            }
        }

        // Global monitor catches keys when another app is focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event, onStop: onStop, onCancel: onCancel)
        }

        // Local monitor catches keys when our app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event, onStop: onStop, onCancel: onCancel)
            return nil // consume the event
        }

        // Return the window number of the first panel so callers can exclude
        // the overlay from CGWindowListCreateImage captures.
        return CGWindowID(panels.first?.windowNumber ?? 0)
    }

    /// Dismisses all overlay panels and cleans up monitors.
    static func dismiss() {
        blinkTimer?.invalidate()
        blinkTimer = nil

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private static func handleKeyEvent(
        _ event: NSEvent,
        onStop: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        switch Int(event.keyCode) {
        case 36, 76: // Return, Numpad Enter
            dismiss()
            onStop()
        case 53: // Escape
            dismiss()
            onCancel()
        default:
            break
        }
    }
}

// MARK: - Overlay View

/// Custom view that draws the blinking red border and the instructional label.
private final class ScrollCaptureOverlayView: NSView {
    let selectionRect: CGRect
    var borderVisible = true {
        didSet { needsDisplay = true }
    }

    init(frame: NSRect, selectionRect: CGRect) {
        self.selectionRect = selectionRect
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        // Convert the screen-coordinate selection rect into this view's coordinate space.
        guard let window = self.window else { return }
        let localRect = window.convertFromScreen(selectionRect)

        // Draw blinking red border fully outside the capture area.
        // insetBy(dx: -4) expands 4px; lineWidth 3 extends ±1.5px from the path,
        // so the inner edge is 2.5px outside the selection — no overlap.
        if borderVisible {
            let borderPath = NSBezierPath(rect: localRect.insetBy(dx: -4, dy: -4))
            borderPath.lineWidth = 3
            NSColor.red.setStroke()
            borderPath.stroke()
        }

        // Draw the label pill above the selection
        let text = "Press ENTER to stop capturing  •  ESC to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let pillWidth = textSize.width + 24
        let pillHeight = textSize.height + 12
        let pillX = localRect.midX - pillWidth / 2
        let pillY = localRect.maxY + 12

        let pillRect = NSRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
        NSColor.black.withAlphaComponent(0.8).setFill()
        pillPath.fill()

        let textPoint = NSPoint(
            x: pillRect.origin.x + 12,
            y: pillRect.origin.y + (pillHeight - textSize.height) / 2
        )
        (text as NSString).draw(at: textPoint, withAttributes: attrs)
    }
}
