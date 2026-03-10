import AppKit
import SwiftUI

/// A standalone window for displaying Znap preferences.
///
/// Used instead of SwiftUI `Settings` scene because `Settings` does not
/// work reliably in LSUIElement (menu-bar-only) apps.
final class PreferencesWindow: NSPanel {

    private static var current: PreferencesWindow?

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "Znap — Preferences"
        isReleasedWhenClosed = false
        animationBehavior = .documentWindow
        center()

        contentView = NSHostingView(rootView: PreferencesView())
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    static func show() {
        if let existing = current, existing.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = PreferencesWindow()
        current = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
