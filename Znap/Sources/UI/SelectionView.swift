import AppKit

/// A custom NSView that handles mouse and keyboard events for interactive
/// screen-region selection.
///
/// When placed inside an ``OverlayWindow``, this view:
/// 1. Dims the entire screen with a semi-transparent black overlay.
/// 2. Draws a "cut-out" rectangle where the user drags, revealing the
///    actual screen content beneath.
/// 3. Strokes the selection rectangle with a white border.
/// 4. Shows a "W x H" dimension label just below the selection.
///
/// Hold **Shift** while dragging to lock the selection to a 1:1 aspect ratio.
/// Press **Escape** to cancel the selection.
final class SelectionView: NSView {
    /// Called when the user completes a valid selection (> 5x5 points).
    var onSelection: ((CGRect) -> Void)?

    /// Called when the user cancels the selection (Escape key).
    var onCancel: (() -> Void)?

    // MARK: - State

    /// The point where the mouse-down event occurred (view coordinates).
    private var startPoint: NSPoint?

    /// The current mouse location during a drag (view coordinates).
    private var currentPoint: NSPoint?

    /// Whether a drag is in progress.
    private var isSelecting = false

    // MARK: - Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool { true }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        startPoint = location
        currentPoint = location
        isSelecting = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isSelecting, let rect = selectionRect else {
            isSelecting = false
            return
        }

        isSelecting = false

        // Only accept selections larger than 5x5 points.
        guard rect.width > 5, rect.height > 5 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }

        // Convert from view-local coordinates to screen coordinates.
        guard let screenRect = window?.convertToScreen(rect) else { return }
        onSelection?(screenRect)
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        // keyCode 53 = Escape
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Fill entire view with semi-transparent black (dim overlay).
        context.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        context.fill(bounds)

        guard let selection = selectionRect else { return }

        // 2. Clear the selection rect to reveal the screen beneath.
        //    Using .copy compositing replaces the dimmed area with clear.
        context.setBlendMode(.copy)
        context.setFillColor(CGColor.clear)
        context.fill(selection)

        // Reset blend mode for subsequent drawing.
        context.setBlendMode(.normal)

        // 3. Stroke the selection rect with a white border.
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        context.stroke(selection)

        // 4. Draw dimension label below the selection.
        drawDimensionLabel(for: selection)
    }

    // MARK: - Private Helpers

    /// Computes the normalized selection rectangle from the start and current points.
    /// If Shift is held, the rectangle is forced to a 1:1 aspect ratio.
    private var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }

        var width = current.x - start.x
        var height = current.y - start.y

        // If Shift is held, lock to 1:1 aspect ratio.
        if NSEvent.modifierFlags.contains(.shift) {
            let side = max(abs(width), abs(height))
            width = width < 0 ? -side : side
            height = height < 0 ? -side : side
        }

        let rect = CGRect(
            x: min(start.x, start.x + width),
            y: min(start.y, start.y + height),
            width: abs(width),
            height: abs(height)
        )

        return rect
    }

    /// Draws a "W x H" dimension label centered below the selection rectangle.
    private func drawDimensionLabel(for rect: CGRect) {
        let w = Int(rect.width)
        let h = Int(rect.height)
        let text = "\(w) \u{00D7} \(h)"

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]

        let textSize = (text as NSString).size(withAttributes: attributes)

        // Position the label centered below the selection, with a small gap.
        let labelX = rect.midX - textSize.width / 2
        let labelY = rect.minY - textSize.height - 6

        // Draw a small rounded background behind the label for readability.
        let padding: CGFloat = 4
        let backgroundRect = CGRect(
            x: labelX - padding,
            y: labelY - padding / 2,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )

        let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        backgroundPath.fill()

        (text as NSString).draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attributes)
    }
}
