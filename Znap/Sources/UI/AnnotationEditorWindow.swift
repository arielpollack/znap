import AppKit
import SwiftUI

/// A floating NSPanel that hosts the annotation editor for a captured screenshot.
///
/// Call ``open(with:)`` to create and display the window. The panel is titled,
/// closable, resizable, and miniaturizable.
final class AnnotationEditorWindow: NSPanel {

    // MARK: - Static State

    /// The currently open annotation editor window, if any.
    private static var current: AnnotationEditorWindow?

    // MARK: - Initialization

    /// Creates an annotation editor window sized to fit the given image.
    ///
    /// - Parameter image: The captured screenshot to annotate.
    private init(image: NSImage) {
        let toolbarHeight: CGFloat = 60
        let padding: CGFloat = 40
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        // Image point dimensions (already scaled for Retina).
        let imgW = image.size.width
        let imgH = image.size.height

        // Desired window size = image + chrome, capped to screen.
        let maxW = screenFrame.width - 40
        let maxH = screenFrame.height - 40
        let contentW = imgW + padding
        let contentH = imgH + toolbarHeight + padding
        let width = min(contentW, maxW)
        let height = min(contentH, maxH)

        let originX = screenFrame.midX - width / 2
        let originY = screenFrame.midY - height / 2

        let contentRect = NSRect(x: originX, y: originY, width: width, height: height)

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "Znap \u{2014} Annotate"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        minSize = NSSize(width: 560, height: 400)
        animationBehavior = .documentWindow

        let editorView = AnnotationEditorView(image: image)
        contentView = NSHostingView(rootView: editorView)
    }

    // MARK: - Key Window

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Public API

    /// Creates and displays an annotation editor window for the given image.
    ///
    /// Closes any previously open annotation editor first.
    ///
    /// - Parameter image: The captured screenshot to annotate.
    static func open(with image: NSImage) {
        // Close the previous editor if one is open.
        current?.close()

        let window = AnnotationEditorWindow(image: image)
        current = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Brings the current editor back to front, if one exists.
    static func restore() {
        guard let window = current, !window.isVisible else {
            guard let window = current else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Whether an editor window currently exists.
    static var hasEditor: Bool { current != nil }
}
