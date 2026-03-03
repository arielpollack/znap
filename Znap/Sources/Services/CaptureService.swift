import ScreenCaptureKit
import CoreGraphics
import AppKit

/// Service that wraps ScreenCaptureKit and CGWindowList APIs for capturing screenshots.
///
/// Provides three capture modes:
/// - Area capture: capture a rectangular region of the screen
/// - Window capture: capture a specific window by its CGWindowID
/// - Fullscreen capture: capture an entire display
///
/// On macOS 14+, area and fullscreen captures use `SCScreenshotManager` for high-quality,
/// Retina-aware output. On macOS 13, a `CGWindowListCreateImage` fallback is used.
/// Window capture always uses `CGWindowListCreateImage`.
final class CaptureService {
    static let shared = CaptureService()

    enum CaptureError: Error {
        case noDisplay
        case captureFailed
        case permissionDenied
    }

    private init() {}

    // MARK: - Area Capture

    /// Capture a rectangular area of the screen.
    ///
    /// The `rect` parameter is in point coordinates (as used by AppKit/NSScreen).
    /// On macOS 14+, ScreenCaptureKit is used and coordinates are converted to pixel
    /// coordinates for Retina displays. On macOS 13, `CGWindowListCreateImage` is used
    /// directly with the point-coordinate rect.
    ///
    /// - Parameter rect: The rectangle to capture, in screen point coordinates.
    /// - Returns: A `CGImage` of the captured area.
    func captureArea(_ rect: CGRect) async throws -> CGImage {
        if #available(macOS 14.0, *) {
            return try await captureAreaWithScreenCaptureKit(rect)
        } else {
            return try captureAreaWithCGWindowList(rect)
        }
    }

    // MARK: - Window Capture

    /// Capture a specific window by its `CGWindowID`.
    ///
    /// Uses `CGWindowListCreateImage` with best-resolution and bounds-ignore-framing options,
    /// which is simpler than ScreenCaptureKit for single-window captures.
    ///
    /// - Parameter windowID: The `CGWindowID` of the window to capture.
    /// - Returns: A `CGImage` of the captured window.
    func captureWindow(_ windowID: CGWindowID) async throws -> CGImage {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            throw CaptureError.captureFailed
        }
        return image
    }

    // MARK: - Fullscreen Capture

    /// Capture the entire screen.
    ///
    /// If a `displayID` is provided, that specific display is captured.
    /// Otherwise, the first available display (typically the primary display) is used.
    ///
    /// - Parameter displayID: Optional `CGDirectDisplayID` to capture. Defaults to the primary display.
    /// - Returns: A `CGImage` of the full display.
    func captureFullscreen(_ displayID: CGDirectDisplayID? = nil) async throws -> CGImage {
        if #available(macOS 14.0, *) {
            return try await captureFullscreenWithScreenCaptureKit(displayID)
        } else {
            return try captureFullscreenWithCGWindowList(displayID)
        }
    }

    // MARK: - macOS 14+ ScreenCaptureKit Implementations

    /// Area capture using `SCScreenshotManager` (macOS 14+).
    ///
    /// Captures the full display at its native pixel resolution, then crops to
    /// the requested rect. Coordinates are converted from AppKit (bottom-left
    /// origin) to CoreGraphics (top-left origin) using the primary screen height.
    @available(macOS 14.0, *)
    private func captureAreaWithScreenCaptureKit(_ rect: CGRect) async throws -> CGImage {
        let content = try await shareableContent()
        guard let display = display(containing: rect.origin, in: content.displays) else {
            throw CaptureError.noDisplay
        }

        // Use the target display's backingScaleFactor, not the main screen's.
        let scale = Self.backingScaleFactor(for: display)
        let displayFrame = display.frame

        // Capture the full display at Retina pixel resolution.
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(displayFrame.width * scale)
        config.height = Int(displayFrame.height * scale)
        config.showsCursor = false
        config.capturesAudio = false

        let fullImage = try await captureImage(filter: filter, configuration: config)

        // Convert NS rect (bottom-left origin) to pixel crop rect (top-left origin).
        // Primary screen height is the reference for NS↔CG conversion.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? displayFrame.height
        let cgRectOriginY = primaryHeight - rect.origin.y - rect.height
        let localX = (rect.origin.x - displayFrame.origin.x) * scale
        let localY = (cgRectOriginY - displayFrame.origin.y) * scale
        let cropW = rect.width * scale
        let cropH = rect.height * scale

        let cropRect = CGRect(x: localX, y: localY, width: cropW, height: cropH)

        guard let cropped = fullImage.cropping(to: cropRect) else {
            throw CaptureError.captureFailed
        }
        return cropped
    }

    /// Fullscreen capture using `SCScreenshotManager` (macOS 14+).
    @available(macOS 14.0, *)
    private func captureFullscreenWithScreenCaptureKit(
        _ displayID: CGDirectDisplayID?
    ) async throws -> CGImage {
        let content = try await shareableContent()

        let display: SCDisplay
        if let displayID = displayID {
            guard let found = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.noDisplay
            }
            display = found
        } else {
            guard let first = content.displays.first else {
                throw CaptureError.noDisplay
            }
            display = first
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.width = Int(display.frame.width * scale)
        config.height = Int(display.frame.height * scale)
        config.showsCursor = false
        config.capturesAudio = false

        return try await captureImage(filter: filter, configuration: config)
    }

    // MARK: - CGWindowList Fallback Implementations

    /// Area capture using `CGWindowListCreateImage` (macOS 13 fallback).
    private func captureAreaWithCGWindowList(_ rect: CGRect) throws -> CGImage {
        guard let image = CGWindowListCreateImage(
            rect,
            .optionAll,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw CaptureError.captureFailed
        }
        return image
    }

    /// Fullscreen capture using `CGWindowListCreateImage` (macOS 13 fallback).
    private func captureFullscreenWithCGWindowList(
        _ displayID: CGDirectDisplayID?
    ) throws -> CGImage {
        let targetDisplayID = displayID ?? CGMainDisplayID()
        let bounds = CGDisplayBounds(targetDisplayID)

        guard let image = CGWindowListCreateImage(
            bounds,
            .optionAll,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw CaptureError.captureFailed
        }
        return image
    }

    // MARK: - Private Helpers

    /// Retrieve shareable content, wrapping the ScreenCaptureKit permission check.
    private func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            // SCShareableContent throws when screen recording permission is not granted.
            throw CaptureError.permissionDenied
        }
    }

    /// Find the display whose frame contains the given point.
    ///
    /// The point is in AppKit (NS) coordinates (bottom-left origin). SCDisplay
    /// frames are in CG coordinates (top-left origin). We convert the NS point
    /// to CG coordinates using the primary screen height.
    ///
    /// - Parameters:
    ///   - nsPoint: A point in NS screen coordinates.
    ///   - displays: The list of available displays.
    /// - Returns: The `SCDisplay` containing the point, or `nil` if none match.
    private func display(containing nsPoint: CGPoint, in displays: [SCDisplay]) -> SCDisplay? {
        // Primary screen height is the reference for NS→CG y conversion.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = CGPoint(x: nsPoint.x, y: primaryHeight - nsPoint.y)
        return displays.first { $0.frame.contains(cgPoint) }
    }

    /// Compute the scale factor (pixels per point) for a given display.
    ///
    /// Uses the ratio of the pixel width (`display.width`) to the point width (`display.frame.width`).
    static func scaleFactor(for display: SCDisplay) -> CGFloat {
        guard display.frame.width > 0 else { return 1.0 }
        return CGFloat(display.width) / display.frame.width
    }

    /// Returns the `backingScaleFactor` for the NSScreen matching the given SCDisplay.
    ///
    /// Falls back to `NSScreen.main?.backingScaleFactor` if no matching screen is found.
    static func backingScaleFactor(for display: SCDisplay) -> CGFloat {
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenNumber == display.displayID {
                return screen.backingScaleFactor
            }
        }
        return NSScreen.main?.backingScaleFactor ?? 2.0
    }

    /// Perform the actual screenshot capture using `SCScreenshotManager` (macOS 14+).
    @available(macOS 14.0, *)
    private func captureImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw CaptureError.captureFailed
        }
    }
}
