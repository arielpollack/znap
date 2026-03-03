import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Encodes an array of `CGImage` frames into an animated GIF file.
///
/// Uses ImageIO's `CGImageDestination` API to write a looping GIF with a
/// configurable frame delay.
///
/// Usage:
/// ```swift
/// let success = GIFEncoder.encode(
///     frames: cgImages,
///     frameDelay: 0.1,
///     outputURL: fileURL
/// )
/// ```
final class GIFEncoder {
    /// Encodes the given frames as an animated GIF and writes to `outputURL`.
    ///
    /// - Parameters:
    ///   - frames: An array of `CGImage` frames to include in the GIF.
    ///   - frameDelay: The delay (in seconds) between each frame.
    ///   - outputURL: The file URL where the GIF will be written.
    /// - Returns: `true` if the GIF was successfully written, `false` otherwise.
    static func encode(frames: [CGImage], frameDelay: TimeInterval, outputURL: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else { return false }

        // Set GIF-level properties: loop forever
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Add each frame with the specified delay
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        return CGImageDestinationFinalize(destination)
    }
}
