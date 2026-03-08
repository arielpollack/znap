import AppKit
import AVFoundation
import AVKit

/// An NSPanel that displays a video preview and timeline editor after a recording
/// stops. The user can split, speed-adjust, delete segments, and export the final
/// edited recording.
///
/// ## Usage
///
/// ```swift
/// VideoEditorPanel.show(videoURL: recordedFileURL)
/// ```
final class VideoEditorPanel: NSPanel {

    // MARK: - Singleton

    /// The currently open video editor panel, if any.
    private static var current: VideoEditorPanel?

    // MARK: - Subviews

    private let playerView = AVPlayerView()
    private let player = AVPlayer()
    private let playPauseButton = NSButton()
    private let splitButton = NSButton()
    private let timeLabel = NSTextField(labelWithString: "0:00 / 0:00")
    private let timelineView = VideoTimelineView(frame: .zero)
    private let speedPopup = NSPopUpButton()
    private let deleteSegmentButton = NSButton()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)

    // MARK: - State

    private var videoURL: URL?
    private var timeObserverToken: Any?
    private var undoStack: [[VideoExportService.Segment]] = []
    private var videoDuration: Double = 0

    // MARK: - Speed Options

    private static let speedOptions: [(title: String, speed: Double)] = [
        ("0.5x", 0.5),
        ("1x", 1.0),
        ("1.5x", 1.5),
        ("2x", 2.0),
        ("4x", 4.0),
    ]

    // MARK: - Initialization

    private init(videoURL: URL) {
        self.videoURL = videoURL

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width: CGFloat = 720
        let height: CGFloat = 480
        let originX = screenFrame.midX - width / 2
        let originY = screenFrame.midY - height / 2
        let contentRect = NSRect(x: originX, y: originY, width: width, height: height)

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        title = "Znap \u{2014} Edit Recording"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .documentWindow
        minSize = NSSize(width: 480, height: 360)

        setupUI()
        loadVideo(url: videoURL)
    }

    // MARK: - Key Window

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - UI Setup

    private func setupUI() {
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        contentView = container

        // Player view
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.controlsStyle = .none
        playerView.player = player
        container.addSubview(playerView)

        // Controls bar
        let controlsBar = NSView()
        controlsBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(controlsBar)

        setupPlayPauseButton()
        controlsBar.addSubview(playPauseButton)

        setupSplitButton()
        controlsBar.addSubview(splitButton)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right
        timeLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        controlsBar.addSubview(timeLabel)

        // Timeline view
        timelineView.translatesAutoresizingMaskIntoConstraints = false
        timelineView.delegate = self
        container.addSubview(timelineView)

        // Segment bar
        let segmentBar = NSView()
        segmentBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(segmentBar)

        setupSpeedPopup()
        segmentBar.addSubview(speedPopup)

        setupDeleteSegmentButton()
        segmentBar.addSubview(deleteSegmentButton)

        // Bottom bar
        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bottomBar)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction)
        bottomBar.addSubview(cancelButton)

        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.target = self
        saveButton.action = #selector(saveAction)
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        if #available(macOS 14.0, *) {
            saveButton.hasDestructiveAction = false
        }
        bottomBar.addSubview(saveButton)

        // Layout
        let padding: CGFloat = 8

        NSLayoutConstraint.activate([
            // Player view — fills available space above controls bar
            playerView.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),

            // Controls bar — 28px tall, below player
            controlsBar.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 4),
            controlsBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            controlsBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            controlsBar.heightAnchor.constraint(equalToConstant: 28),

            // Controls bar contents
            playPauseButton.leadingAnchor.constraint(equalTo: controlsBar.leadingAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: controlsBar.centerYAnchor),

            splitButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 8),
            splitButton.centerYAnchor.constraint(equalTo: controlsBar.centerYAnchor),

            timeLabel.trailingAnchor.constraint(equalTo: controlsBar.trailingAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: controlsBar.centerYAnchor),

            // Timeline — 82px tall, below controls bar
            timelineView.topAnchor.constraint(equalTo: controlsBar.bottomAnchor, constant: 4),
            timelineView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            timelineView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            timelineView.heightAnchor.constraint(equalToConstant: 82),

            // Segment bar — 28px tall, below timeline
            segmentBar.topAnchor.constraint(equalTo: timelineView.bottomAnchor, constant: 4),
            segmentBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            segmentBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            segmentBar.heightAnchor.constraint(equalToConstant: 28),

            // Segment bar contents
            speedPopup.leadingAnchor.constraint(equalTo: segmentBar.leadingAnchor),
            speedPopup.centerYAnchor.constraint(equalTo: segmentBar.centerYAnchor),

            deleteSegmentButton.leadingAnchor.constraint(equalTo: speedPopup.trailingAnchor, constant: 8),
            deleteSegmentButton.centerYAnchor.constraint(equalTo: segmentBar.centerYAnchor),

            // Bottom bar — 32px tall, below segment bar
            bottomBar.topAnchor.constraint(equalTo: segmentBar.bottomAnchor, constant: 4),
            bottomBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            bottomBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            bottomBar.heightAnchor.constraint(equalToConstant: 32),
            bottomBar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),

            // Bottom bar contents
            saveButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            saveButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
        ])
    }

    private func setupPlayPauseButton() {
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.bezelStyle = .rounded
        playPauseButton.isBordered = false
        playPauseButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayPause)
        playPauseButton.toolTip = "Play/Pause"
    }

    private func setupSplitButton() {
        splitButton.translatesAutoresizingMaskIntoConstraints = false
        splitButton.bezelStyle = .rounded
        splitButton.isBordered = false
        splitButton.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Split")
        splitButton.target = self
        splitButton.action = #selector(splitAction)
        splitButton.toolTip = "Split at Playhead"
    }

    private func setupSpeedPopup() {
        speedPopup.translatesAutoresizingMaskIntoConstraints = false
        speedPopup.removeAllItems()
        for option in Self.speedOptions {
            speedPopup.addItem(withTitle: option.title)
        }
        // Default to 1x
        speedPopup.selectItem(withTitle: "1x")
        speedPopup.target = self
        speedPopup.action = #selector(speedChanged)
        speedPopup.toolTip = "Segment Speed"
    }

    private func setupDeleteSegmentButton() {
        deleteSegmentButton.translatesAutoresizingMaskIntoConstraints = false
        deleteSegmentButton.bezelStyle = .rounded
        deleteSegmentButton.isBordered = false
        deleteSegmentButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete Segment")
        deleteSegmentButton.title = "Delete Segment"
        deleteSegmentButton.imagePosition = .imageLeading
        deleteSegmentButton.target = self
        deleteSegmentButton.action = #selector(deleteSegmentAction)
        deleteSegmentButton.toolTip = "Toggle Delete on Selected Segment"
    }

    // MARK: - Video Loading

    private func loadVideo(url: URL) {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)

        // Load duration asynchronously
        Task { [weak self] in
            guard let self else { return }
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)

            await MainActor.run {
                self.videoDuration = durationSeconds
                self.timelineView.duration = durationSeconds

                // Initialize with one segment covering the full duration
                let fullSegment = VideoExportService.Segment(
                    startTime: 0,
                    endTime: durationSeconds,
                    speed: 1.0,
                    deleted: false
                )
                self.timelineView.segments = [fullSegment]
                self.timelineView.selectedSegmentIndex = 0
                self.updateTimeLabel()
                self.generateThumbnails(asset: asset, duration: durationSeconds)
            }
        }

        // Add periodic time observer — also adjusts playback rate for segment speed
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = CMTimeGetSeconds(time)
            self.timelineView.playheadTime = seconds
            self.updateTimeLabel()

            // Adjust playback rate to match current segment speed
            if self.player.rate != 0 {
                self.applySegmentSpeed(at: seconds)
            }
        }

        // Observe end of playback to reset button
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }

    private func generateThumbnails(asset: AVURLAsset, duration: Double) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 160, height: 120)
        generator.appliesPreferredTrackTransform = true

        // Generate roughly one thumbnail per ~2 seconds, capped at 30 thumbnails
        let count = max(1, min(30, Int(duration / 2.0)))
        var times: [NSValue] = []
        for i in 0..<count {
            let seconds = duration * Double(i) / Double(count)
            let cmTime = CMTime(seconds: seconds, preferredTimescale: 600)
            times.append(NSValue(time: cmTime))
        }

        generator.generateCGImagesAsynchronously(forTimes: times) { [weak self] requestedTime, cgImage, _, _, _ in
            guard let self, let cgImage else { return }
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            let timeSeconds = CMTimeGetSeconds(requestedTime)

            DispatchQueue.main.async {
                self.timelineView.thumbnails[timeSeconds] = nsImage
            }
        }
    }

    // MARK: - Time Formatting

    private func updateTimeLabel() {
        let current = timelineView.playheadTime
        let total = videoDuration
        timeLabel.stringValue = "\(formatTime(current)) / \(formatTime(total))"
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Playback Speed

    /// Sets the AVPlayer rate to match the segment speed at the given time.
    private func applySegmentSpeed(at time: Double) {
        guard let idx = timelineView.segments.firstIndex(where: { time >= $0.startTime && time < $0.endTime }) else { return }
        let segment = timelineView.segments[idx]
        let targetRate = segment.deleted ? 0 : Float(segment.speed)
        if abs(player.rate - targetRate) > 0.01 {
            player.rate = targetRate
        }
    }

    // MARK: - Actions

    @objc private func togglePlayPause() {
        if player.rate > 0 {
            player.pause()
            playPauseButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
        } else {
            // If at end, seek to start before playing
            if let currentItem = player.currentItem {
                let currentTime = CMTimeGetSeconds(player.currentTime())
                let duration = CMTimeGetSeconds(currentItem.duration)
                if currentTime >= duration - 0.1 {
                    player.seek(to: .zero)
                }
            }
            let seconds = CMTimeGetSeconds(player.currentTime())
            applySegmentSpeed(at: seconds)
            if player.rate == 0 { player.rate = 1 } // fallback if no segment found
            playPauseButton.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
        }
    }

    @objc private func playerDidFinishPlaying() {
        playPauseButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
    }

    @objc private func splitAction() {
        pushUndo()
        timelineView.splitAtPlayhead()
    }

    @objc private func speedChanged() {
        let index = speedPopup.indexOfSelectedItem
        guard index >= 0, index < Self.speedOptions.count else { return }
        pushUndo()
        timelineView.setSelectedSegmentSpeed(Self.speedOptions[index].speed)
    }

    @objc private func deleteSegmentAction() {
        pushUndo()
        timelineView.toggleDeleteSelectedSegment()
    }

    @objc private func cancelAction() {
        let alert = NSAlert()
        alert.messageText = "Discard Recording?"
        alert.informativeText = "The recording will be permanently deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Keep Editing")

        alert.beginSheetModal(for: self) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                self.cleanupAndDismiss()
            }
        }
    }

    @objc private func saveAction() {
        guard let videoURL else { return }

        saveButton.isEnabled = false
        cancelButton.isEnabled = false

        let segments = timelineView.segments

        Task { [weak self] in
            guard let self else { return }
            do {
                let exportedURL = try await VideoExportService.export(source: videoURL, segments: segments)

                // Generate a thumbnail from the first frame of the exported video
                let exportedAsset = AVURLAsset(url: exportedURL)
                let thumbnailImage = await self.generateThumbnailImage(from: exportedAsset)

                await MainActor.run {
                    if let thumbnail = thumbnailImage {
                        HistoryService.shared.addCapture(
                            type: "recording",
                            image: thumbnail,
                            filePath: exportedURL.path
                        )
                    }
                    self.cleanupAndDismiss()
                }
            } catch {
                await MainActor.run {
                    self.saveButton.isEnabled = true
                    self.cancelButton.isEnabled = true

                    let alert = NSAlert(error: error)
                    alert.beginSheetModal(for: self)
                }
            }
        }
    }

    /// Generates a thumbnail NSImage from the first frame of the given asset.
    private func generateThumbnailImage(from asset: AVURLAsset) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 480)

        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            return NSImage(
                cgImage: cgImage,
                size: NSSize(
                    width: CGFloat(cgImage.width) / scale,
                    height: CGFloat(cgImage.height) / scale
                )
            )
        } catch {
            NSLog("VideoEditorPanel: Failed to generate thumbnail — \(error)")
            return nil
        }
    }

    // MARK: - Undo

    private func pushUndo() {
        undoStack.append(timelineView.segments)
    }

    private func popUndo() {
        guard let previous = undoStack.popLast() else { return }
        timelineView.segments = previous

        // Ensure selected index is valid
        if let selected = timelineView.selectedSegmentIndex,
           selected >= timelineView.segments.count {
            timelineView.selectedSegmentIndex = timelineView.segments.count - 1
        }
        updateSpeedPopupForSelection()
    }

    // MARK: - Keyboard Shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+Z — Undo
        if flags == .command, event.charactersIgnoringModifiers == "z" {
            popUndo()
            return true
        }

        // Space — Play/Pause
        if flags.isEmpty || flags == .function {
            if event.keyCode == 49 { // Space bar
                togglePlayPause()
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Cleanup

    private func cleanupAndDismiss() {
        player.pause()

        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }

        // Remove temp file
        if let url = videoURL {
            try? FileManager.default.removeItem(at: url)
        }

        videoURL = nil
        Self.current = nil
        close()
    }

    // MARK: - Helper

    /// Updates the speed popup to reflect the currently selected segment's speed.
    private func updateSpeedPopupForSelection() {
        guard let index = timelineView.selectedSegmentIndex,
              index >= 0, index < timelineView.segments.count else {
            speedPopup.selectItem(withTitle: "1x")
            return
        }
        let speed = timelineView.segments[index].speed
        if let optionIndex = Self.speedOptions.firstIndex(where: { $0.speed == speed }) {
            speedPopup.selectItem(at: optionIndex)
        }
    }

    // MARK: - Public API

    /// Shows the video editor panel for the given video URL.
    ///
    /// Closes any previously open editor first.
    ///
    /// - Parameter videoURL: URL of the recorded video file.
    static func show(videoURL: URL) {
        dismiss()

        let panel = VideoEditorPanel(videoURL: videoURL)
        current = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Dismisses the currently open video editor, if any.
    static func dismiss() {
        current?.cleanupAndDismiss()
    }
}

// MARK: - VideoTimelineViewDelegate

extension VideoEditorPanel: VideoTimelineViewDelegate {

    func timelineView(_ view: VideoTimelineView, didScrubTo time: Double) {
        player.pause()
        playPauseButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        updateTimeLabel()
    }

    func timelineView(_ view: VideoTimelineView, didSelectSegment index: Int) {
        updateSpeedPopupForSelection()
    }

    func timelineViewDidChangeSegments(_ view: VideoTimelineView) {
        updateSpeedPopupForSelection()
    }
}
