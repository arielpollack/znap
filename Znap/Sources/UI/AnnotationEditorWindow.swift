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
        // Compute a comfortable window size clamped to reasonable maximums.
        let padding: CGFloat = 40
        let toolbarHeight: CGFloat = 60
        let maxWidth: CGFloat = 1200
        let maxHeight: CGFloat = 800
        let width = min(image.size.width + padding, maxWidth)
        let height = min(image.size.height + toolbarHeight + padding, maxHeight)

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
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
        minSize = NSSize(width: 400, height: 300)
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
        window.makeKeyAndOrderFront(nil)
    }
}
