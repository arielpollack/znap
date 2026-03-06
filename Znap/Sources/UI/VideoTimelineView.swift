import AppKit

// MARK: - Delegate Protocol

/// Delegate protocol for responding to timeline interactions.
protocol VideoTimelineViewDelegate: AnyObject {
    /// Called when the user scrubs (clicks or drags) the playhead to a new time.
    func timelineView(_ view: VideoTimelineView, didScrubTo time: Double)

    /// Called when the user selects a segment by clicking on it.
    func timelineView(_ view: VideoTimelineView, didSelectSegment index: Int)

    /// Called when the segment list changes (split, delete toggle, speed change).
    func timelineViewDidChangeSegments(_ view: VideoTimelineView)
}

// MARK: - VideoTimelineView

/// A custom NSView that displays a video timeline with filmstrip thumbnails,
/// split markers, trim handles, segment speed labels, and a playhead.
///
/// The timeline is divided into segments (from `VideoExportService.Segment`) that
/// can be split, deleted, or speed-adjusted. The user can scrub the playhead by
/// clicking or dragging anywhere on the filmstrip.
final class VideoTimelineView: NSView {

    // MARK: - Constants

    /// Width of each trim handle on the left and right edges.
    private let trimHandleWidth: CGFloat = 8

    /// Height of the filmstrip area.
    private let filmstripHeight: CGFloat = 60

    /// Height reserved for speed labels below the filmstrip.
    private let speedLabelHeight: CGFloat = 18

    /// Width of split marker lines.
    private let splitMarkerWidth: CGFloat = 2

    // MARK: - Properties

    /// Delegate for receiving timeline interaction events.
    weak var delegate: VideoTimelineViewDelegate?

    /// Total video duration in seconds.
    var duration: Double = 0 {
        didSet { needsDisplay = true }
    }

    /// Current playhead position in seconds.
    var playheadTime: Double = 0 {
        didSet { needsDisplay = true }
    }

    /// The timeline segments. Each segment defines a time range with optional
    /// speed adjustment or deletion.
    var segments: [VideoExportService.Segment] = [] {
        didSet { needsDisplay = true }
    }

    /// The index of the currently selected segment, if any.
    var selectedSegmentIndex: Int? {
        didSet { needsDisplay = true }
    }

    /// Thumbnail images keyed by their time offset in seconds.
    /// These are displayed across the filmstrip area.
    var thumbnails: [Double: NSImage] = [:] {
        didSet { needsDisplay = true }
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout Helpers

    /// The drawable filmstrip area, inset by the trim handles on each side.
    var filmstripRect: NSRect {
        NSRect(
            x: trimHandleWidth,
            y: speedLabelHeight,
            width: bounds.width - trimHandleWidth * 2,
            height: filmstripHeight
        )
    }

    /// Converts a time value (in seconds) to an x coordinate within the view.
    func xForTime(_ time: Double) -> CGFloat {
        guard duration > 0 else { return trimHandleWidth }
        let strip = filmstripRect
        let fraction = CGFloat(time / duration)
        return strip.minX + fraction * strip.width
    }

    /// Converts an x coordinate within the view to a time value (in seconds).
    func timeForX(_ x: CGFloat) -> Double {
        guard duration > 0 else { return 0 }
        let strip = filmstripRect
        let fraction = Double((x - strip.minX) / strip.width)
        return max(0, min(duration, fraction * duration))
    }

    /// Finds which segment contains the given time.
    func segmentIndex(at time: Double) -> Int? {
        for (index, segment) in segments.enumerated() {
            if time >= segment.startTime && time < segment.endTime {
                return index
            }
        }
        // Edge case: if time equals the very end, return the last segment.
        if let last = segments.last, time >= last.endTime - 0.001 {
            return segments.count - 1
        }
        return nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let strip = filmstripRect

        // 1. Dark gray rounded rect background for the filmstrip area.
        let bgPath = NSBezierPath(roundedRect: strip, xRadius: 4, yRadius: 4)
        NSColor(white: 0.15, alpha: 1).setFill()
        bgPath.fill()

        // 2. Clip and draw thumbnails within the filmstrip.
        context.saveGState()
        context.clip(to: strip)
        drawThumbnails(in: strip)
        context.restoreGState()

        // 3. Draw segment overlays (deleted, selected).
        context.saveGState()
        context.clip(to: strip)
        drawSegmentOverlays(in: strip)
        context.restoreGState()

        // 4. Draw split markers at segment boundaries.
        drawSplitMarkers(in: strip)

        // 5. Draw speed labels below the filmstrip.
        drawSpeedLabels(below: strip)

        // 6. Draw trim handles on left and right edges.
        drawTrimHandles(around: strip)

        // 7. Draw playhead.
        drawPlayhead(in: strip)
    }

    // MARK: - Drawing Subroutines

    /// Draws thumbnails evenly distributed across the filmstrip.
    private func drawThumbnails(in strip: NSRect) {
        guard !thumbnails.isEmpty, duration > 0 else { return }

        // Sort thumbnails by time.
        let sorted = thumbnails.sorted { $0.key < $1.key }
        let count = sorted.count
        guard count > 0 else { return }

        let thumbWidth = strip.width / CGFloat(count)

        for (i, (_, image)) in sorted.enumerated() {
            let destRect = NSRect(
                x: strip.minX + CGFloat(i) * thumbWidth,
                y: strip.minY,
                width: thumbWidth,
                height: strip.height
            )
            image.draw(in: destRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    /// Draws overlays for deleted and selected segments.
    private func drawSegmentOverlays(in strip: NSRect) {
        guard duration > 0 else { return }

        for (index, segment) in segments.enumerated() {
            let x1 = xForTime(segment.startTime)
            let x2 = xForTime(segment.endTime)
            let segRect = NSRect(
                x: x1,
                y: strip.minY,
                width: x2 - x1,
                height: strip.height
            )

            if segment.deleted {
                // Dark overlay for deleted segments.
                NSColor.black.withAlphaComponent(0.6).setFill()
                segRect.fill()

                // Diagonal hatch lines.
                drawHatchPattern(in: segRect)
            }

            if index == selectedSegmentIndex {
                // Blue highlight for selected segment.
                NSColor.systemBlue.withAlphaComponent(0.2).setFill()
                segRect.fill()

                // Blue border around selected segment.
                let borderPath = NSBezierPath(rect: segRect)
                borderPath.lineWidth = 2
                NSColor.systemBlue.setStroke()
                borderPath.stroke()
            }
        }
    }

    /// Draws diagonal hatch lines within a given rect.
    private func drawHatchPattern(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.clip(to: rect)

        let spacing: CGFloat = 8
        let lineWidth: CGFloat = 1

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(lineWidth)

        // Draw diagonal lines from bottom-left to top-right.
        let totalSpan = rect.width + rect.height
        var offset: CGFloat = 0
        while offset < totalSpan {
            let startX = rect.minX + offset
            let startY = rect.minY
            let endX = startX - rect.height
            let endY = rect.maxY

            context.move(to: CGPoint(x: startX, y: startY))
            context.addLine(to: CGPoint(x: endX, y: endY))
            offset += spacing
        }
        context.strokePath()

        context.restoreGState()
    }

    /// Draws yellow vertical lines at each split point (segment boundary).
    private func drawSplitMarkers(in strip: NSRect) {
        guard segments.count > 1 else { return }

        NSColor.yellow.setFill()

        // Draw markers at internal boundaries (skip the first start and last end).
        for i in 1..<segments.count {
            let x = xForTime(segments[i].startTime)
            let markerRect = NSRect(
                x: x - splitMarkerWidth / 2,
                y: strip.minY,
                width: splitMarkerWidth,
                height: strip.height
            )
            markerRect.fill()
        }
    }

    /// Draws speed labels centered below each segment.
    private func drawSpeedLabels(below strip: NSRect) {
        guard duration > 0 else { return }

        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let labelY = strip.minY - speedLabelHeight

        for segment in segments {
            let x1 = xForTime(segment.startTime)
            let x2 = xForTime(segment.endTime)
            let segWidth = x2 - x1

            let label: String
            let color: NSColor
            if segment.deleted {
                label = "DEL"
                color = NSColor.systemRed
            } else if segment.speed == 1.0 {
                label = "1x"
                color = NSColor.secondaryLabelColor
            } else {
                // Format speed: show integer if whole number, otherwise one decimal.
                if segment.speed.truncatingRemainder(dividingBy: 1) == 0 {
                    label = "\(Int(segment.speed))x"
                } else {
                    label = String(format: "%.1fx", segment.speed)
                }
                color = NSColor.systemOrange
            }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            let textSize = (label as NSString).size(withAttributes: attrs)
            let textX = x1 + (segWidth - textSize.width) / 2
            let textY = labelY + (speedLabelHeight - textSize.height) / 2

            (label as NSString).draw(
                at: NSPoint(x: textX, y: textY),
                withAttributes: attrs
            )
        }
    }

    /// Draws white pill-shaped trim handles on the left and right edges.
    private func drawTrimHandles(around strip: NSRect) {
        let handleHeight: CGFloat = 28
        let handleRadius: CGFloat = 3

        // Left trim handle.
        let leftRect = NSRect(
            x: 0,
            y: strip.midY - handleHeight / 2,
            width: trimHandleWidth,
            height: handleHeight
        )
        let leftPath = NSBezierPath(roundedRect: leftRect, xRadius: handleRadius, yRadius: handleRadius)
        NSColor.white.setFill()
        leftPath.fill()

        // Small grip lines on the left handle.
        drawGripLines(in: leftRect)

        // Right trim handle.
        let rightRect = NSRect(
            x: bounds.width - trimHandleWidth,
            y: strip.midY - handleHeight / 2,
            width: trimHandleWidth,
            height: handleHeight
        )
        let rightPath = NSBezierPath(roundedRect: rightRect, xRadius: handleRadius, yRadius: handleRadius)
        NSColor.white.setFill()
        rightPath.fill()

        // Small grip lines on the right handle.
        drawGripLines(in: rightRect)
    }

    /// Draws small horizontal grip lines inside a trim handle rect.
    private func drawGripLines(in rect: NSRect) {
        let lineCount = 3
        let lineSpacing: CGFloat = 3
        let lineWidth: CGFloat = rect.width * 0.5
        let totalHeight = CGFloat(lineCount - 1) * lineSpacing
        let startY = rect.midY - totalHeight / 2

        NSColor(white: 0.4, alpha: 1).setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1

        for i in 0..<lineCount {
            let y = startY + CGFloat(i) * lineSpacing
            let x = rect.midX - lineWidth / 2
            path.move(to: NSPoint(x: x, y: y))
            path.line(to: NSPoint(x: x + lineWidth, y: y))
        }
        path.stroke()
    }

    /// Draws the red playhead line with a small triangle pointer on top.
    private func drawPlayhead(in strip: NSRect) {
        guard duration > 0 else { return }

        let x = xForTime(playheadTime)

        // Red vertical line spanning the filmstrip height.
        let linePath = NSBezierPath()
        linePath.lineWidth = 2
        linePath.move(to: NSPoint(x: x, y: strip.minY))
        linePath.line(to: NSPoint(x: x, y: strip.maxY))
        NSColor.systemRed.setStroke()
        linePath.stroke()

        // Small downward-pointing triangle at the top of the playhead.
        let triangleSize: CGFloat = 8
        let trianglePath = NSBezierPath()
        trianglePath.move(to: NSPoint(x: x - triangleSize / 2, y: strip.maxY))
        trianglePath.line(to: NSPoint(x: x + triangleSize / 2, y: strip.maxY))
        trianglePath.line(to: NSPoint(x: x, y: strip.maxY - triangleSize * 0.7))
        trianglePath.close()

        NSColor.systemRed.setFill()
        trianglePath.fill()
    }

    // MARK: - Mouse Handling

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let time = timeForX(location.x)

        // Select the segment at the clicked position.
        if let index = segmentIndex(at: time) {
            selectedSegmentIndex = index
            delegate?.timelineView(self, didSelectSegment: index)
        }

        // Scrub playhead to click position.
        playheadTime = time
        delegate?.timelineView(self, didScrubTo: time)
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let time = timeForX(location.x)

        playheadTime = time
        delegate?.timelineView(self, didScrubTo: time)
    }

    // MARK: - Public Editing API

    /// Splits the segment at the current playhead position into two segments.
    ///
    /// The segment containing the playhead is divided at `playheadTime`, creating
    /// two new segments that inherit the original segment's speed and deletion state.
    func splitAtPlayhead() {
        guard let index = segmentIndex(at: playheadTime) else { return }

        let segment = segments[index]

        // Don't split if the playhead is at the very start or end of the segment.
        let tolerance = 0.01
        guard playheadTime > segment.startTime + tolerance,
              playheadTime < segment.endTime - tolerance else { return }

        let left = VideoExportService.Segment(
            startTime: segment.startTime,
            endTime: playheadTime,
            speed: segment.speed,
            deleted: segment.deleted
        )
        let right = VideoExportService.Segment(
            startTime: playheadTime,
            endTime: segment.endTime,
            speed: segment.speed,
            deleted: segment.deleted
        )

        segments.replaceSubrange(index...index, with: [left, right])

        // Select the left segment after splitting.
        selectedSegmentIndex = index

        delegate?.timelineViewDidChangeSegments(self)
    }

    /// Toggles the deletion state of the currently selected segment.
    func toggleDeleteSelectedSegment() {
        guard let index = selectedSegmentIndex,
              index >= 0, index < segments.count else { return }

        segments[index].deleted.toggle()

        delegate?.timelineViewDidChangeSegments(self)
    }

    /// Sets the playback speed on the currently selected segment.
    ///
    /// - Parameter speed: The new playback speed multiplier (e.g., 1.0, 2.0, 0.5).
    func setSelectedSegmentSpeed(_ speed: Double) {
        guard let index = selectedSegmentIndex,
              index >= 0, index < segments.count else { return }

        segments[index].speed = speed

        delegate?.timelineViewDidChangeSegments(self)
    }
}
