import AppKit

/// A transparent, full-screen panel used for interactive screen-region selection.
///
/// `OverlayWindow` is an `NSPanel` subclass that covers an entire screen with a
/// nearly invisible window. A ``SelectionView`` is installed as the content view,
/// providing the crosshair cursor, drag-to-select interaction, dimension labels,
/// and dimmed overlay.
///
/// For multi-monitor setups, use ``beginAreaSelection(completion:)`` which creates
/// one overlay per connected screen.
///
/// ## Usage
///
/// ```swift
/// OverlayWindow.beginAreaSelection { rect in
///     guard let rect else { return }  // user cancelled
///     // rect is in screen coordinates, ready for CaptureService
/// }
/// ```
final class OverlayWindow: NSPanel {
    /// Called when the user finishes dragging a valid selection rectangle.
    /// The rect is in screen coordinates (compatible with `CaptureService.captureArea`).
    var onSelection: ((CGRect) -> Void)?

    /// Called when the user cancels the selection (e.g. presses Escape).
    var onCancel: (() -> Void)?

    /// Initializes an overlay window sized to fill the given screen.
    ///
    /// - Parameter screen: The screen this overlay will cover.
    init(for screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.001)
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false

        let selectionView = SelectionView(frame: screen.frame)
        selectionView.onSelection = { [weak self] rect in
            self?.onSelection?(rect)
        }
        selectionView.onCancel = { [weak self] in
            self?.onCancel?()
        }
        contentView = selectionView
    }

    // MARK: - Key/Main Window Overrides

    /// Allow the panel to become the key window so it can receive keyboard events.
    override var canBecomeKey: Bool { true }

    /// Allow the panel to become the main window.
    override var canBecomeMain: Bool { true }

    // MARK: - Static Entry Point

    /// Tracks the currently active overlay windows during a selection session.
    private static var activeWindows: [OverlayWindow] = []

    /// Begins an interactive area-selection session across all connected screens.
    ///
    /// Creates one ``OverlayWindow`` per ``NSScreen``, pushes the crosshair cursor,
    /// and waits for the user to either drag-select a region or press Escape.
    ///
    /// - Parameter completion: Called with the selected `CGRect` in screen
    ///   coordinates, or `nil` if the user cancelled.
    static func beginAreaSelection(completion: @escaping (CGRect?) -> Void) {
        var windows: [OverlayWindow] = []

        let cleanup = {
            NSCursor.pop()
            for window in windows {
                window.orderOut(nil)
            }
            activeWindows.removeAll()
        }

        for screen in NSScreen.screens {
            let overlay = OverlayWindow(for: screen)

            overlay.onSelection = { rect in
                cleanup()
                completion(rect)
            }

            overlay.onCancel = {
                cleanup()
                completion(nil)
            }

            windows.append(overlay)
        }

        activeWindows = windows

        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()

        for window in windows {
            window.makeKeyAndOrderFront(nil)
        }

        // Ensure the first window becomes key so it receives keyboard events.
        windows.first?.makeKey()
    }
}
