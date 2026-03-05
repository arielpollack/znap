import CoreGraphics
import AppKit
import Vision

/// Stitches multiple scroll-captured frames into a single tall screenshot.
///
/// Supports bidirectional scrolling — frames can be stitched above or below
/// previous frames depending on scroll direction. Uses Apple's Vision framework
/// (`VNTranslationalImageRegistrationRequest`) to detect the vertical pixel
/// offset between consecutive frames.
enum ImageStitcher {

    /// Stitches an array of frames captured during scrolling into one image.
    ///
    /// Handles scrolling in any direction (down, up, or mixed). Each frame's
    /// position is determined by the Vision-detected offset from the previous
    /// frame. Near-duplicate frames are automatically dropped.
    static func stitch(images: [CGImage]) -> CGImage? {
        guard !images.isEmpty else { return nil }
        guard images.count > 1 else { return images.first }

        // Compute signed position offsets between consecutive frames.
        var usable: [CGImage] = [images[0]]
        var offsets: [Int] = []

        for i in 1..<images.count {
            let prev = usable.last!
            let cur = images[i]

            guard let offset = findOffset(prev: prev, cur: cur) else {
                continue // near-duplicate, skip
            }

            offsets.append(offset)
            usable.append(cur)
        }

        guard usable.count > 1 else { return usable.first }

        // Calculate absolute y positions (screen coords, y increases downward).
        // Frame 0 starts at y = 0; each subsequent frame is offset from the previous.
        var positions: [Int] = [0]
        for offset in offsets {
            positions.append(positions.last! + offset)
        }

        // Find bounding box.
        let bottoms = positions.enumerated().map { $0.element + usable[$0.offset].height }
        let minY = positions.min()!
        let maxY = bottoms.max()!
        let totalHeight = maxY - minY
        let width = usable.map(\.width).max() ?? 0
        guard width > 0, totalHeight > 0 else { return nil }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: totalHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw frames. Convert screen coords (y-down) to CG coords (y-up).
        for (i, img) in usable.enumerated() {
            let screenY = positions[i] - minY
            let cgY = totalHeight - screenY - img.height
            ctx.draw(img, in: CGRect(x: 0, y: cgY,
                                     width: img.width, height: img.height))
        }

        return ctx.makeImage()
    }

    // MARK: - Offset Detection via Vision Framework

    /// Returns the signed y-offset (in screen coordinates) from `prev` to `cur`.
    ///
    /// - Positive offset: `cur` is below `prev` (user scrolled down).
    /// - Negative offset: `cur` is above `prev` (user scrolled up).
    /// - `nil`: near-duplicate frame (should be skipped).
    private static func findOffset(prev: CGImage, cur: CGImage) -> Int? {
        let minH = min(prev.height, cur.height)

        // Crop to the middle 60 % both horizontally and vertically to avoid
        // scrollbar / window-shadow edges and fixed headers / footers.
        let cropW = prev.width * 3 / 5
        let cropX = (prev.width - cropW) / 2
        let cropH = prev.height * 3 / 5
        let cropY = (prev.height - cropH) / 2

        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
        guard let prevCropped = prev.cropping(to: cropRect),
              let curCropped = cur.cropping(to: cropRect) else { return 0 }

        // reference = prev, target = cur.
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: curCropped)
        let handler = VNImageRequestHandler(cgImage: prevCropped, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return 0
        }

        guard let observation = request.results?.first
                as? VNImageTranslationAlignmentObservation else { return 0 }

        let rawTy = observation.alignmentTransform.ty
        let absShift = Int(round(abs(rawTy)))

        // Tiny shift → near-duplicate.
        guard absShift > 3 else { return nil }

        // Shift must be less than frame height (otherwise alignment failed).
        guard absShift < minH else { return 0 }

        // Require at least 5 % overlap for the alignment to be trustworthy.
        let overlap = minH - absShift
        guard overlap >= minH * 5 / 100 else { return 0 }

        // Vision's alignmentTransform.ty is in CG coordinates (y-up):
        //   ty < 0 → user scrolled down → new frame below → positive screen offset
        //   ty > 0 → user scrolled up → new frame above → negative screen offset
        return -Int(round(rawTy))
    }
}
