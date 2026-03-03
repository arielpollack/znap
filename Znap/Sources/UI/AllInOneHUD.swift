import AppKit
import Carbon
import SwiftUI

/// A floating HUD panel that presents all capture modes as clickable icons.
///
/// The HUD appears centered on screen when triggered by the All-In-One hotkey
/// (Cmd+Shift+1). Each icon represents a capture mode (area, window, fullscreen,
/// scroll, record, OCR). Clicking an icon dismisses the HUD and starts the
/// corresponding capture flow.
///
/// ## Usage
///
/// ```swift
/// AllInOneHUD.show(with: [
///     Mode(id: "area", icon: "rectangle.dashed", label: "Area", shortcut: "⌘⇧4") {
///         appDelegate.startAreaCapture()
///     }
/// ])
/// ```
final class AllInOneHUD: NSPanel {

    // MARK: - Mode

    /// Describes a single capture mode displayed in the HUD.
    struct Mode: Identifiable {
        let id: String
        /// SF Symbol name for the mode icon.
        let icon: String
        /// Short display label shown beneath the icon.
        let label: String
        /// Human-readable keyboard shortcut hint.
        let shortcut: String
        /// Action invoked when the user clicks this mode.
        let action: () -> Void
    }

    // MARK: - Static State

    /// The currently visible HUD instance, if any.
    private static var current: AllInOneHUD?

    // MARK: - Initialization

    /// Creates a new HUD panel configured with the provided modes.
    ///
    /// - Parameter modes: The capture modes to display.
    private init(modes: [Mode]) {
        let panelSize = NSSize(width: 380, height: 70)
        let screenFrame = NSScreen.main?.frame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.midY - panelSize.height / 2 + 60
        )

        super.init(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .transient]
        animationBehavior = .utilityWindow

        let hostingView = NSHostingView(rootView: AllInOneHUDContent(modes: modes))
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        contentView = hostingView
    }

    // MARK: - Key Window

    override var canBecomeKey: Bool { true }

    // MARK: - Escape to Dismiss

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            Self.dismiss()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Static API

    /// Shows the All-In-One HUD with the given modes.
    ///
    /// If a HUD is already visible, it is replaced.
    ///
    /// - Parameter modes: The capture modes to display.
    static func show(with modes: [Mode]) {
        dismiss()

        let hud = AllInOneHUD(modes: modes)
        current = hud

        NSApp.activate(ignoringOtherApps: true)
        hud.alphaValue = 0
        hud.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            hud.animator().alphaValue = 1
        }
    }

    /// Dismisses the currently visible HUD, if any.
    static func dismiss() {
        guard let hud = current else { return }
        current = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            hud.animator().alphaValue = 0
        }, completionHandler: {
            hud.orderOut(nil)
        })
    }
}

// MARK: - SwiftUI Content

/// The SwiftUI view displayed inside the All-In-One HUD panel.
///
/// Renders a horizontal row of icon buttons, each showing an SF Symbol and a label.
/// The entire view uses `.ultraThinMaterial` as its background with rounded corners.
private struct AllInOneHUDContent: View {
    let modes: [AllInOneHUD.Mode]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(modes) { mode in
                Button(action: {
                    AllInOneHUD.dismiss()
                    mode.action()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 22))
                        Text(mode.label)
                            .font(.system(size: 10))
                    }
                    .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("\(mode.label) (\(mode.shortcut))")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 380, height: 70)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}
