import AppKit
import Carbon

/// A floating capsule-shaped panel that appears during screen recording to show
/// elapsed time and provide pause/stop controls.
///
/// The panel displays a pulsing red dot, a running time label, and compact
/// pause/stop buttons. It sits at the top-center of the screen and is draggable.
///
/// ## Usage
///
/// ```swift
/// RecordingIndicatorPanel.show()
/// RecordingIndicatorPanel.dismiss()
/// ```
final class RecordingIndicatorPanel: NSPanel {

    // MARK: - Static State

    /// The currently visible indicator panel, if any. Only one panel is shown at a time.
    private(set) static var current: RecordingIndicatorPanel?

    /// The `CGWindowID` of the current panel, for SCStream exclusion.
    /// Returns 0 if no panel is visible.
    static var windowID: CGWindowID {
        guard let panel = current else { return 0 }
        return CGWindowID(panel.windowNumber)
    }

    // MARK: - Instance Properties

    /// Timer that updates the elapsed time label.
    private var updateTimer: Timer?

    /// Timer that drives the pulsing red dot animation.
    private var pulseTimer: Timer?

    /// The red dot indicator view.
    private let dotView = NSView()

    /// The elapsed time label.
    private let timeLabel = NSTextField(labelWithString: "0:00")

    /// The pause/resume button.
    private let pauseButton = NSButton()

    /// The stop button.
    private let stopButton = NSButton()

    /// Current pulse direction: true = fading in, false = fading out.
    private var pulsingUp = false

    // MARK: - Initialization

    /// Creates a new recording indicator panel positioned at the top-center of the main screen.
    private init() {
        let panelSize = NSSize(width: 200, height: 36)
        let screenFrame = NSScreen.main?.frame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.maxY - panelSize.height - 12
        )

        super.init(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .transient]
        animationBehavior = .utilityWindow

        setupContentView(size: panelSize)
    }

    // MARK: - Key Window

    override var canBecomeKey: Bool { true }

    // MARK: - Escape to Dismiss (triggers stop)

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Content Setup

    /// Builds the pill-shaped visual effect background and lays out all subviews.
    private func setupContentView(size: NSSize) {
        // Background: NSVisualEffectView with hudWindow material, pill-shaped
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = size.height / 2
        effectView.layer?.masksToBounds = true

        // Red dot
        let dotSize: CGFloat = 10
        dotView.frame = NSRect(x: 14, y: (size.height - dotSize) / 2, width: dotSize, height: dotSize)
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        dotView.layer?.cornerRadius = dotSize / 2
        effectView.addSubview(dotView)

        // Time label
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        timeLabel.textColor = .white
        timeLabel.alignment = .left
        timeLabel.isBezeled = false
        timeLabel.isEditable = false
        timeLabel.drawsBackground = false
        timeLabel.sizeToFit()
        timeLabel.frame.origin = NSPoint(x: 30, y: (size.height - timeLabel.frame.height) / 2)
        effectView.addSubview(timeLabel)

        // Pause button
        configurePauseButton(paused: false)
        pauseButton.frame = NSRect(x: size.width - 68, y: (size.height - 24) / 2, width: 28, height: 24)
        pauseButton.isBordered = false
        pauseButton.target = self
        pauseButton.action = #selector(pauseTapped)
        effectView.addSubview(pauseButton)

        // Stop button
        let stopImage = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop recording")
        stopButton.image = stopImage
        stopButton.contentTintColor = .systemRed
        stopButton.imageScaling = .scaleProportionallyDown
        stopButton.frame = NSRect(x: size.width - 36, y: (size.height - 24) / 2, width: 28, height: 24)
        stopButton.isBordered = false
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        (stopButton.cell as? NSButtonCell)?.imageScaling = .scaleProportionallyDown
        effectView.addSubview(stopButton)

        contentView = effectView
    }

    /// Configures the pause button icon based on the current paused state.
    private func configurePauseButton(paused: Bool) {
        let symbolName = paused ? "play.fill" : "pause.fill"
        let description = paused ? "Resume recording" : "Pause recording"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        pauseButton.image = image
        pauseButton.contentTintColor = .white
        pauseButton.imageScaling = .scaleProportionallyDown
        (pauseButton.cell as? NSButtonCell)?.imageScaling = .scaleProportionallyDown
    }

    // MARK: - Actions

    @objc private func pauseTapped() {
        RecordingService.shared.togglePause()
        let isPaused = RecordingService.shared.isPaused
        configurePauseButton(paused: isPaused)
    }

    @objc private func stopTapped() {
        stopRecording()
    }

    /// Stops the recording by calling through to AppDelegate.
    private func stopRecording() {
        (NSApp.delegate as? AppDelegate)?.toggleRecording()
    }

    // MARK: - Timers

    /// Starts the elapsed time update timer and the red dot pulse timer.
    private func startTimers() {
        // Update elapsed time every 0.25s
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateTimeLabel()
        }

        // Pulse the red dot opacity between 0.2 and 1.0
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.animatePulse()
        }
    }

    /// Stops all running timers.
    private func stopTimers() {
        updateTimer?.invalidate()
        updateTimer = nil
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    /// Reads `RecordingService.shared.elapsedTime` and updates the time label.
    private func updateTimeLabel() {
        let elapsed = RecordingService.shared.elapsedTime
        let totalSeconds = Int(elapsed)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        timeLabel.stringValue = String(format: "%d:%02d", minutes, seconds)
        timeLabel.sizeToFit()
    }

    /// Oscillates the red dot opacity between 0.2 and 1.0.
    private func animatePulse() {
        guard let layer = dotView.layer else { return }
        var opacity = Float(layer.opacity)

        if pulsingUp {
            opacity += 0.03
            if opacity >= 1.0 {
                opacity = 1.0
                pulsingUp = false
            }
        } else {
            opacity -= 0.03
            if opacity <= 0.2 {
                opacity = 0.2
                pulsingUp = true
            }
        }

        layer.opacity = opacity
    }

    // MARK: - Static API

    /// Shows the recording indicator panel at the top-center of the screen.
    ///
    /// If a panel is already visible, it is replaced.
    static func show() {
        dismiss()

        let panel = RecordingIndicatorPanel()
        current = panel

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        panel.startTimers()
    }

    /// Dismisses the currently visible recording indicator panel, if any.
    static func dismiss() {
        guard let panel = current else { return }
        current = nil

        panel.stopTimers()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}
