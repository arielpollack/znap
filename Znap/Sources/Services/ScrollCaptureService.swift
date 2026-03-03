import CoreGraphics
import AppKit

/// Service that performs scrolling capture by programmatically scrolling a region
/// and stitching the captured frames together.
///
/// The service captures an initial frame, sends scroll events to advance the content,
/// captures subsequent frames, and uses ``ImageStitcher`` to combine them into a
/// single tall (or wide) image.
///
/// ## Usage
///
/// ```swift
/// let image = try await ScrollCaptureService.shared.captureScrolling(in: rect)
/// ```
final class ScrollCaptureService {
    static let shared = ScrollCaptureService()

    private init() {}

    /// The direction of scrolling.
    enum ScrollDirection {
        case vertical
        case horizontal
    }

    enum ScrollCaptureError: Error {
        case captureFailed
        case noFramesCaptured
        case stitchFailed
    }

    /// Maximum number of frames to capture in a single scroll session.
    private let maxFrames = 50

    /// Delay in seconds between scroll and next capture, allowing content to settle.
    private let scrollSettleDelay: TimeInterval = 0.2

    /// Captures a scrolling region by auto-scrolling and stitching frames.
    ///
    /// - Parameters:
    ///   - rect: The screen region to capture, in point coordinates.
    ///   - direction: The scroll direction. Defaults to `.vertical`.
    /// - Returns: A single stitched `CGImage` of the scrolled content.
    func captureScrolling(
        in rect: CGRect,
        direction: ScrollDirection = .vertical
    ) async throws -> CGImage {
        var frames: [CGImage] = []

        // 1. Capture initial frame
        guard let firstFrame = captureRegion(rect) else {
            throw ScrollCaptureError.captureFailed
        }
        frames.append(firstFrame)

        // 2. Scroll and capture loop
        for _ in 1..<maxFrames {
            // Send scroll event
            sendScrollEvent(direction: direction)

            // Wait for scroll to settle
            try await Task.sleep(nanoseconds: UInt64(scrollSettleDelay * 1_000_000_000))

            // Capture next frame
            guard let frame = captureRegion(rect) else { continue }

            // Compare with previous frame — if identical, stop
            if isDuplicate(frame, previous: frames.last!) {
                break
            }

            frames.append(frame)
        }

        guard !frames.isEmpty else {
            throw ScrollCaptureError.noFramesCaptured
        }

        // If only one frame was captured, return it directly
        if frames.count == 1 {
            return frames[0]
        }

        // Stitch all frames
        guard let stitched = ImageStitcher.stitch(images: frames) else {
            throw ScrollCaptureError.stitchFailed
        }

        return stitched
    }

    // MARK: - Private Helpers

    /// Captures a region of the screen using CGWindowListCreateImage.
    private func captureRegion(_ rect: CGRect) -> CGImage? {
        CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
    }

    /// Sends a scroll wheel event in the specified direction.
    private func sendScrollEvent(direction: ScrollDirection) {
        let wheel1: Int32 = direction == .vertical ? -5 : 0
        let wheel2: Int32 = direction == .horizontal ? -5 : 0

        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: wheel1,
            wheel2: wheel2,
            wheel3: 0
        ) else { return }

        event.post(tap: .cgSessionEventTap)
    }

    /// Checks whether two frames are essentially identical (duplicate).
    ///
    /// Compares a sample of pixels from both images. If more than 98% of sampled
    /// pixels are identical, the frames are considered duplicates.
    private func isDuplicate(_ current: CGImage, previous: CGImage) -> Bool {
        guard current.width == previous.width,
              current.height == previous.height else { return false }

        guard let currentData = current.dataProvider?.data,
              let previousData = previous.dataProvider?.data else { return false }

        let currentPtr = CFDataGetBytePtr(currentData)
        let previousPtr = CFDataGetBytePtr(previousData)

        guard let currentPtr, let previousPtr else { return false }

        let bytesPerRow = current.bytesPerRow
        let height = current.height
        let width = current.width
        let bytesPerPixel = bytesPerRow / width

        guard bytesPerPixel > 0 else { return false }

        var matchCount = 0
        var sampleCount = 0

        // Sample pixels at regular intervals
        for y in stride(from: 0, to: height, by: 8) {
            for x in stride(from: 0, to: width, by: 8) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                var isMatch = true
                for c in 0..<min(bytesPerPixel, 3) {
                    if abs(Int(currentPtr[offset + c]) - Int(previousPtr[offset + c])) > 5 {
                        isMatch = false
                        break
                    }
                }
                if isMatch { matchCount += 1 }
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return true }
        return matchCount * 100 / sampleCount >= 98
    }
}
