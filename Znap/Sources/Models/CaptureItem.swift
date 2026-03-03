import AppKit
import SwiftData

/// A SwiftData model representing a single capture in the history.
///
/// Each ``CaptureItem`` records the capture type, dimensions, file size, and an
/// optional thumbnail for display in the history list. The ``filePath`` property
/// stores the location of the saved file on disk (if any).
@available(macOS 14, *)
@Model
final class CaptureItem {
    /// Unique identifier for this capture.
    var id: UUID
    /// Timestamp when the capture was taken.
    var timestamp: Date
    /// A string describing the capture type (e.g. "area", "window", "fullscreen").
    var captureType: String
    /// Path to the saved file on disk, if the capture was saved.
    var filePath: String?
    /// JPEG thumbnail data for quick preview.
    var thumbnailData: Data?
    /// Width of the captured image in pixels.
    var width: Int
    /// Height of the captured image in pixels.
    var height: Int
    /// Size of the saved file in bytes.
    var fileSize: Int64

    /// Creates a new capture item.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID).
    ///   - timestamp: When the capture was taken (defaults to now).
    ///   - captureType: Kind of capture (e.g. "area", "window").
    ///   - filePath: Optional file path for the saved image.
    ///   - thumbnailData: Optional JPEG data for thumbnail preview.
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - fileSize: File size in bytes.
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        captureType: String,
        filePath: String? = nil,
        thumbnailData: Data? = nil,
        width: Int = 0,
        height: Int = 0,
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.captureType = captureType
        self.filePath = filePath
        self.thumbnailData = thumbnailData
        self.width = width
        self.height = height
        self.fileSize = fileSize
    }
}

// MARK: - NSImage Thumbnail Extension

extension NSImage {
    /// Returns a resized copy of the image that fits within the given size,
    /// preserving the original aspect ratio.
    ///
    /// - Parameter targetSize: The maximum bounding size for the result.
    /// - Returns: A new ``NSImage`` scaled to fit within `targetSize`.
    func resized(to targetSize: NSSize) -> NSImage {
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let scale = min(widthRatio, heightRatio)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        draw(
            in: NSRect(origin: .zero, size: newSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }
}
