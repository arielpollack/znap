import CoreGraphics
import AppKit

/// Service that passively captures frames while the user manually scrolls,
/// then stitches them into a single tall image.
///
/// Uses ``CaptureService`` (ScreenCaptureKit) for each frame capture so it
/// works on modern macOS where `CGWindowListCreateImage` is unavailable.
///
/// ## Usage
///
/// ```swift
/// ScrollCaptureService.shared.startCapturing(in: rect)
/// // ... user scrolls ...
/// if let image = ScrollCaptureService.shared.stopCapturing() {
///     // show stitched image
/// }
/// ```
final class ScrollCaptureService {
    static let shared = ScrollCaptureService()

    private init() {}

    private var frames: [CGImage] = []
    private var isCapturing = false
    private var captureTimer: Timer?
    /// Guards against overlapping async captures.
    private var isBusy = false

    /// Begins periodic frame capture of the given screen region.
    ///
    /// - Parameter rect: The screen region in AppKit coordinates (bottom-left origin).
    func startCapturing(in rect: CGRect) {
        frames = []
        isCapturing = true
        isBusy = false

        // Capture a frame every 150ms using CaptureService (ScreenCaptureKit).
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.timerFired(rect: rect)
        }

        // Also capture the first frame immediately.
        timerFired(rect: rect)
    }

    /// Stops capturing and returns the stitched image, or `nil` if stitching
    /// failed or no frames were captured.
    @discardableResult
    func stopCapturing() -> CGImage? {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil

        guard !frames.isEmpty else { return nil }

        if frames.count == 1 {
            let result = frames[0]
            frames = []
            return result
        }

        let result = ImageStitcher.stitch(images: frames)
        frames = []
        return result
    }

    // MARK: - Private Helpers

    /// Called by the timer; kicks off an async capture via CaptureService.
    private func timerFired(rect: CGRect) {
        guard isCapturing, !isBusy else { return }
        isBusy = true

        Task {
            defer {
                DispatchQueue.main.async { self.isBusy = false }
            }
            guard let frame = try? await CaptureService.shared.captureArea(rect) else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.appendIfUnique(frame)
            }
        }
    }

    /// Appends the frame only if it differs from the last captured frame.
    private func appendIfUnique(_ frame: CGImage) {
        if let last = frames.last {
            if !isDuplicate(frame, previous: last) {
                frames.append(frame)
            }
        } else {
            frames.append(frame)
        }
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
        // 99.5% threshold — filters out frames with trivial scroll amounts
        // (1-5px) that don't add meaningful new content.
        return matchCount * 1000 / sampleCount >= 995
    }
}
