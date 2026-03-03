import CoreGraphics
import AppKit

/// Utility for stitching multiple images vertically (or horizontally) into a single image.
///
/// Used by ``ScrollCaptureService`` to combine multiple scroll-captured frames
/// into one tall screenshot, automatically detecting and removing overlap between
/// consecutive frames.
enum ImageStitcher {

    /// Stitches images vertically, detecting overlap between consecutive frames.
    ///
    /// For each consecutive pair, overlap is detected and removed so the final image
    /// appears seamless. If only one image is provided, it is returned as-is.
    ///
    /// - Parameter images: An array of `CGImage` frames to stitch, in order from top to bottom.
    /// - Returns: A single stitched `CGImage`, or `nil` if the input array is empty.
    static func stitch(images: [CGImage]) -> CGImage? {
        guard !images.isEmpty else { return nil }
        guard images.count > 1 else { return images.first }

        // Calculate overlaps between consecutive pairs
        var overlaps: [Int] = []
        for i in 0..<(images.count - 1) {
            let overlap = findOverlap(top: images[i], bottom: images[i + 1])
            overlaps.append(overlap)
        }

        // Calculate total height = sum of all image heights minus all overlaps
        let totalHeight = images.reduce(0) { $0 + $1.height } - overlaps.reduce(0, +)
        let width = images.map(\.width).max() ?? 0

        guard width > 0, totalHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw images from top to bottom
        // CGContext has origin at bottom-left, so we draw from top (highest y) downward
        var yOffset = totalHeight

        for (index, image) in images.enumerated() {
            yOffset -= image.height
            let drawRect = CGRect(x: 0, y: yOffset, width: image.width, height: image.height)
            context.draw(image, in: drawRect)

            // Add back the overlap for the next image positioning
            if index < overlaps.count {
                yOffset += overlaps[index]
            }
        }

        return context.makeImage()
    }

    /// Finds pixel overlap between the bottom of the `top` image and the top of the `bottom` image.
    ///
    /// Compares rows by sampling every 4th row for speed, using only the middle 50% of each row
    /// to avoid scrollbar artifacts at the edges. A row is considered matching if the average
    /// per-channel difference is below a threshold.
    ///
    /// - Parameters:
    ///   - top: The upper image.
    ///   - bottom: The lower image.
    ///   - maxSearch: Maximum number of rows to search for overlap. Default is 200.
    /// - Returns: The number of overlapping pixel rows, or 0 if no overlap is found.
    private static func findOverlap(top: CGImage, bottom: CGImage, maxSearch: Int = 200) -> Int {
        let topWidth = top.width
        let bottomWidth = bottom.width

        guard topWidth > 0, bottomWidth > 0 else { return 0 }

        // We need pixel data access
        guard let topData = top.dataProvider?.data,
              let bottomData = bottom.dataProvider?.data else { return 0 }

        let topPtr = CFDataGetBytePtr(topData)
        let bottomPtr = CFDataGetBytePtr(bottomData)

        guard let topPtr, let bottomPtr else { return 0 }

        let topBytesPerRow = top.bytesPerRow
        let bottomBytesPerRow = bottom.bytesPerRow

        let topHeight = top.height
        let bottomHeight = bottom.height

        let searchLimit = min(maxSearch, min(topHeight, bottomHeight))

        // Middle 50% of row to compare (skip edges for scrollbar artifacts)
        let compareWidth = min(topWidth, bottomWidth)
        let startX = compareWidth / 4
        let endX = startX + compareWidth / 2
        let bytesPerPixel = topBytesPerRow / topWidth

        guard bytesPerPixel > 0, endX > startX else { return 0 }

        // Try overlap sizes from large to small
        // stride by -4 for speed (sample every 4th overlap size)
        for overlapSize in stride(from: searchLimit, through: 10, by: -4) {
            var matches = 0
            var totalChecked = 0

            // Sample every 4th row within this overlap region
            for rowOffset in stride(from: 0, to: overlapSize, by: 4) {
                let topRow = topHeight - overlapSize + rowOffset
                let bottomRow = rowOffset

                guard topRow >= 0, topRow < topHeight,
                      bottomRow >= 0, bottomRow < bottomHeight else { continue }

                var rowDiff: Int = 0
                var pixelCount = 0

                for x in stride(from: startX, to: endX, by: 2) {
                    let topOffset = topRow * topBytesPerRow + x * bytesPerPixel
                    let bottomOffset = bottomRow * bottomBytesPerRow + x * bytesPerPixel

                    // Compare RGB channels (skip alpha)
                    let channels = min(bytesPerPixel, 3)
                    for c in 0..<channels {
                        let diff = abs(Int(topPtr[topOffset + c]) - Int(bottomPtr[bottomOffset + c]))
                        rowDiff += diff
                    }
                    pixelCount += 1
                }

                guard pixelCount > 0 else { continue }

                let avgDiff = rowDiff / (pixelCount * min(bytesPerPixel, 3))
                if avgDiff < 30 {
                    matches += 1
                }
                totalChecked += 1
            }

            // If most sampled rows match, we found the overlap
            if totalChecked > 0, matches * 100 / totalChecked >= 80 {
                return overlapSize
            }
        }

        return 0
    }
}
