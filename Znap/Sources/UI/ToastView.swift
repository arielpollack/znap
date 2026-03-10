// ToastView.swift
import AppKit

/// A lightweight, non-activating floating HUD that displays a brief message
/// and fades out automatically.
@MainActor
final class ToastPanel: NSPanel {
    private static var current: ToastPanel?

    private init(message: String, icon: String? = nil) {
        // Size and position: centered horizontally, lower third of screen
        let width: CGFloat = 280
        let height: CGFloat = 44
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screen.midX - width / 2,
            y: screen.minY + screen.height * 0.25
        )
        super.init(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true

        // Visual effect background
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: NSSize(width: width, height: height)))
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = height / 2
        blur.layer?.masksToBounds = true

        // Label
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center

        // Icon (optional)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        if let iconName = icon {
            let imageView = NSImageView()
            imageView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            imageView.contentTintColor = .white
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            stack.addArrangedSubview(imageView)
        }
        stack.addArrangedSubview(label)
        stack.translatesAutoresizingMaskIntoConstraints = false

        blur.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
        ])

        contentView = blur
    }

    /// Shows a toast message that auto-dismisses after the given duration.
    static func show(_ message: String, icon: String? = nil, duration: TimeInterval = 1.5) {
        current?.orderOut(nil)

        let panel = ToastPanel(message: message, icon: icon)
        current = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    panel.animator().alphaValue = 0
                }) {
                    panel.orderOut(nil)
                    if Self.current === panel { Self.current = nil }
                }
            }
        }
    }
}
