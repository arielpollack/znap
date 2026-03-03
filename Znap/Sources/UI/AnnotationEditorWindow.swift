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

    // MARK: - Keyboard Shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags == .command {
            switch event.charactersIgnoringModifiers {
            case "z":
                NotificationCenter.default.post(name: .annotationUndo, object: nil)
                return true
            case "c":
                NotificationCenter.default.post(name: .annotationCopy, object: nil)
                return true
            case "s":
                NotificationCenter.default.post(name: .annotationSave, object: nil)
                return true
            default:
                break
            }
        }

        if flags == [.command, .shift] {
            if event.charactersIgnoringModifiers == "z" {
                NotificationCenter.default.post(name: .annotationRedo, object: nil)
                return true
            }
        }

        if flags.isEmpty || flags == .function {
            let keyCode = event.keyCode
            // Delete (51) or Forward Delete (117)
            if keyCode == 51 || keyCode == 117 {
                NotificationCenter.default.post(name: .annotationDelete, object: nil)
                return true
            }
        }

        // Single-key tool shortcuts (only when no text field is active).
        if flags.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased(),
           !(firstResponder is NSTextView) {
            if let tool = Self.toolForKey(key) {
                NotificationCenter.default.post(
                    name: .annotationSelectTool,
                    object: nil,
                    userInfo: ["tool": tool.rawValue]
                )
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Tool Key Mapping

    /// Maps single-key presses to annotation tool types.
    private static func toolForKey(_ key: String) -> AnnotationDocument.AnnotationType? {
        switch key {
        case "a": return .arrow
        case "r": return .rectangle
        case "f": return .filledRectangle
        case "o": return .ellipse
        case "l": return .line
        case "t": return .text
        case "n": return .counter
        case "x": return .pixelate
        case "b": return .blur
        case "s": return .spotlight
        case "h": return .highlighter
        case "p": return .pencil
        case "w": return .handwriting
        default:  return nil
        }
    }

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

// MARK: - Annotation Notification Names

extension Notification.Name {
    static let annotationUndo       = Notification.Name("annotationUndo")
    static let annotationRedo       = Notification.Name("annotationRedo")
    static let annotationCopy       = Notification.Name("annotationCopy")
    static let annotationSave       = Notification.Name("annotationSave")
    static let annotationDelete     = Notification.Name("annotationDelete")
    static let annotationSelectTool = Notification.Name("annotationSelectTool")
}
