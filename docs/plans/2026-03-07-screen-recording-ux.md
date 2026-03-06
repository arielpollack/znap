# Screen Recording UX Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a floating recording indicator pill, and a post-recording video editor with timeline splitting, speed control, trim, and MP4 export.

**Architecture:** Four new files — a floating pill panel for recording state, a video editor panel with embedded AVPlayer, a custom timeline view for split/trim/speed editing, and an export service using AVMutableComposition. The existing `AppDelegate.toggleRecording()` is modified to show the pill on start and open the editor on stop.

**Tech Stack:** AppKit (NSPanel, NSView, NSVisualEffectView, CABasicAnimation), AVFoundation (AVPlayer, AVPlayerLayer, AVMutableComposition, AVAssetExportSession, AVAssetImageGenerator), ScreenCaptureKit (SCContentFilter window exclusion)

---

### Task 1: RecordingIndicatorPanel — Floating Pill

**Files:**
- Create: `Znap/Sources/UI/RecordingIndicatorPanel.swift`

**Step 1: Create the floating pill panel**

```swift
import AppKit
import Carbon

/// A small floating capsule shown during screen recording, displaying elapsed
/// time and providing stop/pause controls.
///
/// The panel is excluded from the recording via SCStream window exclusion.
/// It appears top-center on the recorded display and is draggable.
///
/// ## Usage
///
/// ```swift
/// RecordingIndicatorPanel.show()
/// RecordingIndicatorPanel.dismiss()
/// ```
final class RecordingIndicatorPanel: NSPanel {

    // MARK: - Static State

    private(set) static var current: RecordingIndicatorPanel?

    // MARK: - Instance Properties

    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let dotView = NSView()
    private var dotAnimation: Timer?
    private var updateTimer: Timer?

    // MARK: - Initialization

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

        setupContent()
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Content Setup

    private func setupContent() {
        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        container.material = .hudWindow
        container.state = .active
        container.blendingMode = .behindWindow
        container.wantsLayer = true
        container.layer?.cornerRadius = frame.height / 2
        container.layer?.masksToBounds = true
        contentView = container

        // Red dot
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        dotView.layer?.cornerRadius = 5
        dotView.frame = NSRect(x: 14, y: 13, width: 10, height: 10)
        container.addSubview(dotView)

        // Time label
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        timeLabel.textColor = .white
        timeLabel.frame = NSRect(x: 30, y: 8, width: 60, height: 20)
        container.addSubview(timeLabel)

        // Pause button
        let pauseBtn = makeButton(icon: "pause.fill", x: 100, action: #selector(pauseTapped))
        container.addSubview(pauseBtn)

        // Stop button
        let stopBtn = makeButton(icon: "stop.fill", x: 140, action: #selector(stopTapped))
        stopBtn.contentTintColor = .systemRed
        container.addSubview(stopBtn)
    }

    private func makeButton(icon: String, x: CGFloat, action: Selector) -> NSButton {
        let btn = NSButton(frame: NSRect(x: x, y: 4, width: 28, height: 28))
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        btn.contentTintColor = .white
        btn.target = self
        btn.action = action
        btn.imagePosition = .imageOnly
        btn.imageScaling = .scaleProportionallyDown
        return btn
    }

    // MARK: - Actions

    @objc private func pauseTapped() {
        RecordingService.shared.togglePause()
        updatePauseIcon()
    }

    @objc private func stopTapped() {
        // AppDelegate handles the stop flow
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.toggleRecording()
        }
    }

    private func updatePauseIcon() {
        let isPaused = RecordingService.shared.isPaused
        let icon = isPaused ? "play.fill" : "pause.fill"
        if let container = contentView,
           let pauseBtn = container.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.frame.origin.x == 100 }) {
            pauseBtn.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        }
    }

    // MARK: - Timer Updates

    private func startUpdating() {
        // Pulsing red dot
        dotAnimation = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            let isPaused = RecordingService.shared.isPaused
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                self.dotView.animator().alphaValue = (self.dotView.alphaValue < 1) || isPaused ? 1 : 0.2
            }
        }

        // Elapsed time
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = RecordingService.shared.elapsedTime
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            self.timeLabel.stringValue = String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func stopUpdating() {
        dotAnimation?.invalidate()
        dotAnimation = nil
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Escape Key

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopTapped()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Static API

    /// The window number for SCStream exclusion.
    static var windowID: CGWindowID? {
        guard let panel = current else { return nil }
        return CGWindowID(panel.windowNumber)
    }

    static func show() {
        dismiss()

        let panel = RecordingIndicatorPanel()
        current = panel

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }

        panel.startUpdating()
    }

    static func dismiss() {
        guard let panel = current else { return }
        current = nil
        panel.stopUpdating()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}
```

**Step 2: Commit**

```
git add Znap/Sources/UI/RecordingIndicatorPanel.swift
git commit -m "feat: add RecordingIndicatorPanel floating pill"
```

---

### Task 2: Wire Indicator into Recording Flow + Window Exclusion

**Files:**
- Modify: `Znap/Sources/AppDelegate.swift` (toggleRecording method)
- Modify: `Znap/Sources/Services/RecordingService.swift` (add window exclusion)

**Step 1: Add window exclusion to RecordingService**

In `RecordingService.swift`, change the `SCContentFilter` creation (around line 91-97) to accept excluded window IDs. Add a property and modify `startRecording`:

Add a new property after line 53:
```swift
private var excludedWindowIDs: [CGWindowID] = []
```

Change the `startRecording` method signature to:
```swift
func startRecording(config: RecordingConfig, excludeWindowIDs: [CGWindowID] = []) async throws {
```

Store the IDs:
```swift
excludedWindowIDs = excludeWindowIDs
```

Replace the content filter creation block (lines 91-97) to exclude windows by ID:
```swift
let filter: SCContentFilter
if let windowID = config.windowID,
   let window = content.windows.first(where: { $0.windowID == windowID }) {
    filter = SCContentFilter(desktopIndependentWindow: window)
} else {
    let excludeWindows = content.windows.filter { excludeWindowIDs.contains($0.windowID) }
    filter = SCContentFilter(display: display, excludingWindows: excludeWindows)
}
```

**Step 2: Update AppDelegate.toggleRecording()**

Replace the entire `toggleRecording()` method:

```swift
func toggleRecording() {
    let windowTitle = Self.frontmostWindowName()
    Task { @MainActor in
        let service = RecordingService.shared
        if service.isRecording {
            // Dismiss indicator and stop recording
            RecordingIndicatorPanel.dismiss()
            if let url = await service.stopRecording() {
                VideoEditorPanel.show(videoURL: url)
            }
        } else {
            // Show area selection overlay, then start recording
            OverlayWindow.beginAreaSelection { rect in
                guard let rect = rect else { return }
                Task { @MainActor in
                    do {
                        // Show indicator first so we can get its window ID
                        RecordingIndicatorPanel.show()
                        let excludeIDs = [RecordingIndicatorPanel.windowID].compactMap { $0 }
                        let config = RecordingService.RecordingConfig(rect: rect)
                        try await RecordingService.shared.startRecording(
                            config: config,
                            excludeWindowIDs: excludeIDs
                        )
                    } catch {
                        RecordingIndicatorPanel.dismiss()
                        print("Recording failed to start: \(error)")
                    }
                }
            }
        }
    }
}
```

**Step 3: Commit**

```
git add Znap/Sources/AppDelegate.swift Znap/Sources/Services/RecordingService.swift
git commit -m "feat: wire recording indicator into recording flow with window exclusion"
```

---

### Task 3: VideoExportService — Composition + Export

**Files:**
- Create: `Znap/Sources/Services/VideoExportService.swift`

**Step 1: Create the export service**

```swift
import AVFoundation

/// Exports an edited video by composing segments with optional speed changes
/// and removed sections using `AVMutableComposition`.
///
/// ## Usage
///
/// ```swift
/// let segments = [
///     VideoExportService.Segment(startTime: 0, endTime: 5, speed: 1.0, deleted: false),
///     VideoExportService.Segment(startTime: 5, endTime: 8, speed: 2.0, deleted: false),
///     VideoExportService.Segment(startTime: 8, endTime: 12, speed: 1.0, deleted: true),
/// ]
/// let url = try await VideoExportService.export(source: sourceURL, segments: segments)
/// ```
enum VideoExportService {

    /// A segment of the video timeline with its speed and deletion state.
    struct Segment {
        /// Start time in the original video (seconds).
        let startTime: Double
        /// End time in the original video (seconds).
        let endTime: Double
        /// Playback speed multiplier (1.0 = normal).
        var speed: Double = 1.0
        /// Whether this segment is deleted (excluded from export).
        var deleted: Bool = false

        var duration: Double { endTime - startTime }
        var cmTimeRange: CMTimeRange {
            CMTimeRange(
                start: CMTime(seconds: startTime, preferredTimescale: 600),
                duration: CMTime(seconds: duration, preferredTimescale: 600)
            )
        }
    }

    enum ExportError: Error {
        case noVideoTrack
        case exportFailed(String)
        case exportCancelled
    }

    /// Exports the edited video to the Desktop.
    ///
    /// - Parameters:
    ///   - source: URL of the original recorded video.
    ///   - segments: The timeline segments with speed and deletion info.
    /// - Returns: URL of the exported file.
    static func export(source: URL, segments: [Segment]) async throws -> URL {
        let asset = AVURLAsset(url: source)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }

        let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
        let audioTrack = audioTracks?.first

        let composition = AVMutableComposition()

        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.noVideoTrack
        }

        let compAudioTrack: AVMutableCompositionTrack?
        if audioTrack != nil {
            compAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        } else {
            compAudioTrack = nil
        }

        var insertTime = CMTime.zero

        for segment in segments where !segment.deleted {
            let timeRange = segment.cmTimeRange

            try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: insertTime)
            if let audioTrack, let compAudioTrack {
                try compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: insertTime)
            }

            let segDuration = timeRange.duration

            if segment.speed != 1.0 {
                let scaledDuration = CMTime(
                    seconds: segDuration.seconds / segment.speed,
                    preferredTimescale: 600
                )
                let insertedRange = CMTimeRange(start: insertTime, duration: segDuration)
                compVideoTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                compAudioTrack?.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                insertTime = insertTime + scaledDuration
            } else {
                insertTime = insertTime + segDuration
            }
        }

        // Output path
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "Znap-\(timestamp).mp4"
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let outputURL = desktopURL.appendingPathComponent(filename)

        // Export
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportFailed("Could not create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return outputURL
        case .cancelled:
            throw ExportError.exportCancelled
        default:
            throw ExportError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown error")
        }
    }
}
```

**Step 2: Commit**

```
git add Znap/Sources/Services/VideoExportService.swift
git commit -m "feat: add VideoExportService for composition and export"
```

---

### Task 4: VideoTimelineView — Custom Timeline

**Files:**
- Create: `Znap/Sources/UI/VideoTimelineView.swift`

**Step 1: Create the timeline view**

```swift
import AppKit
import AVFoundation

/// A custom timeline view that displays video frames as a filmstrip with
/// split markers, trim handles, and per-segment speed labels.
///
/// The timeline reports user interactions (scrub, split, select segment,
/// trim) through its `delegate`.
///
/// ## Layout
///
/// ```
/// [trim handle] |▓▓▓▓▓▓▓|▓▓▓▓|░░░░░|▓▓▓▓▓▓▓▓| [trim handle]
///                [1x]    [2x]  [DEL]  [1x]
/// ```
protocol VideoTimelineViewDelegate: AnyObject {
    /// Called when the user scrubs to a new time position.
    func timelineView(_ view: VideoTimelineView, didScrubTo time: Double)
    /// Called when the user clicks on a segment.
    func timelineView(_ view: VideoTimelineView, didSelectSegment index: Int)
    /// Called when the user modifies segments (split, trim, delete, speed change).
    func timelineViewDidChangeSegments(_ view: VideoTimelineView)
}

final class VideoTimelineView: NSView {

    weak var delegate: VideoTimelineViewDelegate?

    /// Total duration of the source video in seconds.
    var duration: Double = 0 {
        didSet { needsDisplay = true }
    }

    /// Current playhead position in seconds.
    var playheadTime: Double = 0 {
        didSet { needsDisplay = true }
    }

    /// The segments describing the timeline.
    var segments: [VideoExportService.Segment] = [] {
        didSet { needsDisplay = true }
    }

    /// Index of the currently selected segment, if any.
    var selectedSegmentIndex: Int? {
        didSet { needsDisplay = true }
    }

    /// Thumbnail images keyed by time offset (seconds), generated externally.
    var thumbnails: [Double: NSImage] = [:] {
        didSet { needsDisplay = true }
    }

    // MARK: - Layout Constants

    private let trimHandleWidth: CGFloat = 8
    private let timelineHeight: CGFloat = 60
    private let segmentLabelHeight: CGFloat = 18
    private let markerWidth: CGFloat = 2

    // MARK: - Computed

    /// The drawable area for the filmstrip (excluding trim handles).
    private var filmstripRect: NSRect {
        NSRect(
            x: trimHandleWidth,
            y: segmentLabelHeight,
            width: bounds.width - trimHandleWidth * 2,
            height: timelineHeight
        )
    }

    /// Convert a time value to an x coordinate within the filmstrip.
    private func xForTime(_ time: Double) -> CGFloat {
        guard duration > 0 else { return filmstripRect.minX }
        return filmstripRect.minX + CGFloat(time / duration) * filmstripRect.width
    }

    /// Convert an x coordinate to a time value.
    private func timeForX(_ x: CGFloat) -> Double {
        guard filmstripRect.width > 0 else { return 0 }
        let clamped = max(filmstripRect.minX, min(x, filmstripRect.maxX))
        return Double((clamped - filmstripRect.minX) / filmstripRect.width) * duration
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard duration > 0 else { return }

        let filmstrip = filmstripRect

        // Draw filmstrip background
        NSColor.darkGray.setFill()
        NSBezierPath(roundedRect: filmstrip, xRadius: 4, yRadius: 4).fill()

        // Draw thumbnails
        let thumbCount = max(1, Int(filmstrip.width / 80))
        let thumbWidth = filmstrip.width / CGFloat(thumbCount)
        for i in 0..<thumbCount {
            let time = duration * Double(i) / Double(thumbCount)
            if let img = thumbnails[time] {
                let thumbRect = NSRect(
                    x: filmstrip.minX + CGFloat(i) * thumbWidth,
                    y: filmstrip.minY,
                    width: thumbWidth,
                    height: filmstrip.height
                )
                img.draw(in: thumbRect)
            }
        }

        // Draw segments (highlight selected, dim deleted)
        for (i, seg) in segments.enumerated() {
            let x1 = xForTime(seg.startTime)
            let x2 = xForTime(seg.endTime)
            let segRect = NSRect(x: x1, y: filmstrip.minY, width: x2 - x1, height: filmstrip.height)

            if seg.deleted {
                NSColor.black.withAlphaComponent(0.6).setFill()
                segRect.fill()
                // Hatched pattern
                let path = NSBezierPath()
                var hx = segRect.minX
                while hx < segRect.maxX {
                    path.move(to: NSPoint(x: hx, y: segRect.minY))
                    path.line(to: NSPoint(x: hx + segRect.height, y: segRect.maxY))
                    hx += 8
                }
                NSColor.gray.withAlphaComponent(0.5).setStroke()
                path.lineWidth = 1
                path.stroke()
            }

            if i == selectedSegmentIndex {
                NSColor.systemBlue.withAlphaComponent(0.2).setFill()
                segRect.fill()
                NSColor.systemBlue.setStroke()
                NSBezierPath(rect: segRect).stroke()
            }

            // Speed label below segment
            let speedText = seg.deleted ? "DEL" : "\(seg.speed)x"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: seg.deleted ? NSColor.systemRed : NSColor.secondaryLabelColor,
            ]
            let textSize = (speedText as NSString).size(withAttributes: attrs)
            let labelX = x1 + (x2 - x1 - textSize.width) / 2
            (speedText as NSString).draw(
                at: NSPoint(x: labelX, y: 1),
                withAttributes: attrs
            )
        }

        // Draw split markers (yellow lines between segments)
        for i in 1..<segments.count {
            let x = xForTime(segments[i].startTime)
            let markerRect = NSRect(x: x - 1, y: filmstrip.minY, width: markerWidth, height: filmstrip.height)
            NSColor.systemYellow.setFill()
            markerRect.fill()
        }

        // Draw trim handles
        let leftHandle = NSRect(x: 0, y: filmstrip.minY, width: trimHandleWidth, height: filmstrip.height)
        let rightHandle = NSRect(x: bounds.width - trimHandleWidth, y: filmstrip.minY, width: trimHandleWidth, height: filmstrip.height)
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: leftHandle, xRadius: 2, yRadius: 2).fill()
        NSBezierPath(roundedRect: rightHandle, xRadius: 2, yRadius: 2).fill()

        // Draw playhead (red vertical line)
        let playX = xForTime(playheadTime)
        NSColor.systemRed.setFill()
        NSRect(x: playX - 1, y: filmstrip.minY - 4, width: 2, height: filmstrip.height + 8).fill()

        // Playhead triangle
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: playX - 5, y: filmstrip.maxY + 4))
        tri.line(to: NSPoint(x: playX + 5, y: filmstrip.maxY + 4))
        tri.line(to: NSPoint(x: playX, y: filmstrip.maxY - 2))
        tri.close()
        NSColor.systemRed.setFill()
        tri.fill()
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let time = timeForX(loc.x)

        // Check if clicking on a segment for selection
        if let idx = segmentIndex(at: time) {
            selectedSegmentIndex = idx
            delegate?.timelineView(self, didSelectSegment: idx)
        }

        // Scrub to position
        playheadTime = time
        delegate?.timelineView(self, didScrubTo: time)
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let time = timeForX(loc.x)
        playheadTime = time
        delegate?.timelineView(self, didScrubTo: time)
    }

    // MARK: - Segment Lookup

    private func segmentIndex(at time: Double) -> Int? {
        segments.firstIndex { time >= $0.startTime && time < $0.endTime }
    }

    // MARK: - Public Editing API

    /// Adds a split at the current playhead position.
    func splitAtPlayhead() {
        guard let idx = segmentIndex(at: playheadTime) else { return }
        let seg = segments[idx]
        guard playheadTime > seg.startTime && playheadTime < seg.endTime else { return }

        let left = VideoExportService.Segment(
            startTime: seg.startTime, endTime: playheadTime, speed: seg.speed, deleted: seg.deleted
        )
        let right = VideoExportService.Segment(
            startTime: playheadTime, endTime: seg.endTime, speed: seg.speed, deleted: seg.deleted
        )
        segments.replaceSubrange(idx...idx, with: [left, right])
        selectedSegmentIndex = nil
        delegate?.timelineViewDidChangeSegments(self)
    }

    /// Toggles deletion of the selected segment.
    func toggleDeleteSelectedSegment() {
        guard let idx = selectedSegmentIndex else { return }
        segments[idx].deleted.toggle()
        delegate?.timelineViewDidChangeSegments(self)
    }

    /// Sets the speed of the selected segment.
    func setSelectedSegmentSpeed(_ speed: Double) {
        guard let idx = selectedSegmentIndex else { return }
        segments[idx].speed = speed
        delegate?.timelineViewDidChangeSegments(self)
    }
}
```

**Step 2: Commit**

```
git add Znap/Sources/UI/VideoTimelineView.swift
git commit -m "feat: add VideoTimelineView with split markers, trim, and speed"
```

---

### Task 5: VideoEditorPanel — Editor Window

**Files:**
- Create: `Znap/Sources/UI/VideoEditorPanel.swift`

**Step 1: Create the editor panel**

```swift
import AppKit
import AVFoundation
import AVKit

/// A floating panel that shows a video preview and timeline editor after
/// recording stops. Supports splitting, deleting segments, changing speed,
/// trimming, and exporting as MP4.
///
/// ## Usage
///
/// ```swift
/// VideoEditorPanel.show(videoURL: url)
/// ```
final class VideoEditorPanel: NSPanel {

    // MARK: - Static State

    private static var current: VideoEditorPanel?

    // MARK: - Instance Properties

    private let videoURL: URL
    private let player: AVPlayer
    private let playerView: AVPlayerView
    private let timelineView: VideoTimelineView
    private let timeLabel = NSTextField(labelWithString: "0:00 / 0:00")
    private let playButton: NSButton
    private let splitButton: NSButton
    private var timeObserver: Any?
    private var undoStack: [[VideoExportService.Segment]] = []

    // MARK: - Initialization

    private init(videoURL: URL) {
        self.videoURL = videoURL

        let asset = AVURLAsset(url: videoURL)
        player = AVPlayer(url: videoURL)

        playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = false

        timelineView = VideoTimelineView()

        playButton = NSButton()
        splitButton = NSButton()

        let panelSize = NSSize(width: 720, height: 480)
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.midY - panelSize.height / 2
        )

        super.init(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "Znap — Edit Recording"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 480, height: 360)
        animationBehavior = .documentWindow

        setupUI()
        loadAssetInfo(asset: asset)
    }

    // MARK: - UI Setup

    private func setupUI() {
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        contentView = container

        // Player view (fills top area)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(playerView)

        // Controls bar
        let controlsBar = NSView()
        controlsBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(controlsBar)

        // Play button
        playButton.bezelStyle = .inline
        playButton.isBordered = false
        playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
        playButton.contentTintColor = .labelColor
        playButton.target = self
        playButton.action = #selector(togglePlay)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        controlsBar.addSubview(playButton)

        // Split button
        splitButton.bezelStyle = .inline
        splitButton.title = "Split"
        splitButton.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Split")
        splitButton.imagePosition = .imageLeading
        splitButton.target = self
        splitButton.action = #selector(splitAtPlayhead)
        splitButton.translatesAutoresizingMaskIntoConstraints = false
        controlsBar.addSubview(splitButton)

        // Time label
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        controlsBar.addSubview(timeLabel)

        // Timeline
        timelineView.translatesAutoresizingMaskIntoConstraints = false
        timelineView.delegate = self
        container.addSubview(timelineView)

        // Segment controls (speed + delete) - shown inline below timeline
        let segmentBar = NSView()
        segmentBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(segmentBar)

        // Speed popup
        let speedPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        speedPopup.addItems(withTitles: ["0.5x", "1x", "1.5x", "2x", "4x"])
        speedPopup.selectItem(withTitle: "1x")
        speedPopup.target = self
        speedPopup.action = #selector(speedChanged(_:))
        speedPopup.translatesAutoresizingMaskIntoConstraints = false
        speedPopup.tag = 100
        segmentBar.addSubview(speedPopup)

        // Delete segment button
        let deleteBtn = NSButton()
        deleteBtn.bezelStyle = .inline
        deleteBtn.title = "Delete Segment"
        deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteBtn.imagePosition = .imageLeading
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteSegment)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        segmentBar.addSubview(deleteBtn)

        // Bottom bar (Cancel + Save)
        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bottomBar)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(cancelBtn)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(saveBtn)

        // Layout
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),

            controlsBar.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 8),
            controlsBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            controlsBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            controlsBar.heightAnchor.constraint(equalToConstant: 28),

            playButton.leadingAnchor.constraint(equalTo: controlsBar.leadingAnchor),
            playButton.centerYAnchor.constraint(equalTo: controlsBar.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 28),

            splitButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 12),
            splitButton.centerYAnchor.constraint(equalTo: controlsBar.centerYAnchor),

            timeLabel.trailingAnchor.constraint(equalTo: controlsBar.trailingAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: controlsBar.centerYAnchor),

            timelineView.topAnchor.constraint(equalTo: controlsBar.bottomAnchor, constant: 8),
            timelineView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            timelineView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            timelineView.heightAnchor.constraint(equalToConstant: 82),

            segmentBar.topAnchor.constraint(equalTo: timelineView.bottomAnchor, constant: 4),
            segmentBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            segmentBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            segmentBar.heightAnchor.constraint(equalToConstant: 28),

            speedPopup.leadingAnchor.constraint(equalTo: segmentBar.leadingAnchor),
            speedPopup.centerYAnchor.constraint(equalTo: segmentBar.centerYAnchor),

            deleteBtn.leadingAnchor.constraint(equalTo: speedPopup.trailingAnchor, constant: 12),
            deleteBtn.centerYAnchor.constraint(equalTo: segmentBar.centerYAnchor),

            bottomBar.topAnchor.constraint(equalTo: segmentBar.bottomAnchor, constant: 12),
            bottomBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            bottomBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            bottomBar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            bottomBar.heightAnchor.constraint(equalToConstant: 32),

            saveBtn.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            saveBtn.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -8),
            cancelBtn.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            playerView.bottomAnchor.constraint(equalTo: controlsBar.topAnchor, constant: -8),
        ])
    }

    // MARK: - Asset Loading

    private func loadAssetInfo(asset: AVURLAsset) {
        Task {
            let duration = try await asset.load(.duration)
            let totalSeconds = duration.seconds

            await MainActor.run {
                self.timelineView.duration = totalSeconds
                self.timelineView.segments = [
                    VideoExportService.Segment(startTime: 0, endTime: totalSeconds)
                ]
                self.updateTimeLabel()
                self.generateThumbnails(asset: asset, duration: totalSeconds)
                self.startTimeObserver()
            }
        }
    }

    private func generateThumbnails(asset: AVURLAsset, duration: Double) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 120)

        let count = max(1, Int(timelineView.filmstripRect.width / 80))
        var times: [NSValue] = []
        for i in 0..<count {
            let time = CMTime(seconds: duration * Double(i) / Double(count), preferredTimescale: 600)
            times.append(NSValue(time: time))
        }

        generator.generateCGImagesAsynchronously(forTimes: times) { [weak self] requestedTime, cgImage, _, _, _ in
            guard let cgImage else { return }
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            DispatchQueue.main.async {
                self?.timelineView.thumbnails[requestedTime.seconds] = nsImage
            }
        }
    }

    // MARK: - Time Observer

    private func startTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.timelineView.playheadTime = time.seconds
            self.updateTimeLabel()
        }
    }

    private func updateTimeLabel() {
        let current = player.currentTime().seconds
        let total = timelineView.duration
        timeLabel.stringValue = "\(formatTime(current)) / \(formatTime(total))"
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let mins = Int(s) / 60
        let secs = Int(s) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Actions

    @objc private func togglePlay() {
        if player.rate > 0 {
            player.pause()
            playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
        } else {
            player.play()
            playButton.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
        }
    }

    @objc private func splitAtPlayhead() {
        pushUndo()
        timelineView.splitAtPlayhead()
    }

    @objc private func deleteSegment() {
        pushUndo()
        timelineView.toggleDeleteSelectedSegment()
    }

    @objc private func speedChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        let speed = Double(title.replacingOccurrences(of: "x", with: "")) ?? 1.0
        pushUndo()
        timelineView.setSelectedSegmentSpeed(speed)
    }

    @objc private func cancelTapped() {
        let alert = NSAlert()
        alert.messageText = "Discard Recording?"
        alert.informativeText = "The recording will be permanently deleted."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Keep Editing")
        alert.alertStyle = .warning

        alert.beginSheetModal(for: self) { response in
            if response == .alertFirstButtonReturn {
                try? FileManager.default.removeItem(at: self.videoURL)
                Self.dismiss()
            }
        }
    }

    @objc private func saveTapped() {
        let segments = timelineView.segments
        Task {
            do {
                let outputURL = try await VideoExportService.export(source: videoURL, segments: segments)
                await MainActor.run {
                    // Add to history
                    let asset = AVURLAsset(url: outputURL)
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                        let thumbnail = NSImage(
                            cgImage: cgImage,
                            size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
                        )
                        HistoryService.shared.addCapture(type: "recording", image: thumbnail)
                    }
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: self.videoURL)
                    Self.dismiss()
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert(error: error as NSError)
                    alert.beginSheetModal(for: self)
                }
            }
        }
    }

    // MARK: - Undo

    private func pushUndo() {
        undoStack.append(timelineView.segments)
    }

    override func keyDown(with event: NSEvent) {
        // Cmd+Z for undo
        if event.modifierFlags.contains(.command) && event.keyCode == 6 /* Z */ {
            if let prev = undoStack.popLast() {
                timelineView.segments = prev
            }
        } else {
            super.keyDown(with: event)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Static API

    static func show(videoURL: URL) {
        dismiss()

        let panel = VideoEditorPanel(videoURL: videoURL)
        current = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    static func dismiss() {
        if let panel = current {
            if let observer = panel.timeObserver {
                panel.player.removeTimeObserver(observer)
            }
            panel.player.pause()
            panel.orderOut(nil)
        }
        current = nil
    }
}

// MARK: - VideoTimelineViewDelegate

extension VideoEditorPanel: VideoTimelineViewDelegate {
    func timelineView(_ view: VideoTimelineView, didScrubTo time: Double) {
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func timelineView(_ view: VideoTimelineView, didSelectSegment index: Int) {
        // Update speed popup to reflect selected segment's speed
        if let segmentBar = contentView?.subviews.first(where: { view in
            view.subviews.contains(where: { ($0 as? NSPopUpButton)?.tag == 100 })
        }),
           let popup = segmentBar.subviews.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.tag == 100 }) {
            let speed = timelineView.segments[index].speed
            popup.selectItem(withTitle: "\(speed)x")
        }
    }

    func timelineViewDidChangeSegments(_ view: VideoTimelineView) {
        // Segments changed — could update duration preview etc.
    }
}
```

**Step 2: Add `filmstripRect` to public API in VideoTimelineView**

The `filmstripRect` property in `VideoTimelineView` is currently `private`. The `VideoEditorPanel` needs it to calculate thumbnail count. Make it `internal`:

Change `private var filmstripRect` to just `var filmstripRect` in `VideoTimelineView.swift`.

**Step 3: Commit**

```
git add Znap/Sources/UI/VideoEditorPanel.swift Znap/Sources/UI/VideoTimelineView.swift
git commit -m "feat: add VideoEditorPanel with player, timeline, and editing controls"
```

---

### Task 6: Build, Test, and Fix

**Step 1: Build the project**

```
make run
```

**Step 2: Fix any compilation errors**

Address any Swift compiler errors. Common issues to watch for:
- Missing `@MainActor` annotations on methods called from async contexts
- `filmstripRect` access level
- AVFoundation API differences between macOS versions

**Step 3: Manual test**

1. Press Cmd+Shift+R → select area → recording starts
2. Verify floating pill appears with pulsing red dot and timer
3. Click Stop on pill → verify editor opens with video
4. Test split, delete segment, speed change
5. Test Save → verify MP4 appears on Desktop
6. Test Cancel → verify confirmation dialog

**Step 4: Commit fixes**

```
git add -A
git commit -m "fix: resolve build issues in recording UI"
```
