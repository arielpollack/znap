import AppKit
import CoreImage

/// Core Image filter utilities for annotation effects such as pixelation, blur,
/// and spotlight (dimming everything outside a selected region).
enum ImageFilters {

    // MARK: - Shared CIContext

    /// A reusable Core Image context for rendering filter output.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Pixelate

    /// Applies a pixelation (mosaic) effect to a rectangular region of the image.
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - region: The rectangle (in image coordinates) to pixelate.
    ///   - scale: The pixel block size. Larger values produce coarser pixelation.
    /// - Returns: The composited image with the selected region pixelated,
    ///   or `nil` if the filter chain fails.
    static func pixelate(image: CGImage, region: CGRect, scale: CGFloat = 20) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let fullExtent = ciImage.extent

        guard let pixelFilter = CIFilter(name: "CIPixellate") else { return nil }
        pixelFilter.setValue(ciImage, forKey: kCIInputImageKey)
        pixelFilter.setValue(scale, forKey: kCIInputScaleKey)
        pixelFilter.setValue(CIVector(cgPoint: CGPoint(x: region.midX, y: region.midY)),
                             forKey: kCIInputCenterKey)

        guard let pixelated = pixelFilter.outputImage else { return nil }

        // Crop the pixelated output to the region, then composite over the original.
        let cropped = pixelated.cropped(to: region)
        let composited = cropped.composited(over: ciImage)

        return ciContext.createCGImage(composited, from: fullExtent)
    }

    // MARK: - Blur

    /// Applies a Gaussian blur to a rectangular region of the image.
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - region: The rectangle (in image coordinates) to blur.
    ///   - radius: The blur radius.
    /// - Returns: The composited image with the selected region blurred,
    ///   or `nil` if the filter chain fails.
    static func blur(image: CGImage, region: CGRect, radius: CGFloat = 10) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let fullExtent = ciImage.extent

        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let blurred = blurFilter.outputImage else { return nil }

        // CIGaussianBlur expands the image extent; crop back to the region.
        let cropped = blurred.cropped(to: region)
        let composited = cropped.composited(over: ciImage)

        return ciContext.createCGImage(composited, from: fullExtent)
    }

    // MARK: - Spotlight

    /// Dims everything outside the selected region, creating a spotlight effect.
    ///
    /// The region itself remains fully bright; the rest of the image is darkened
    /// by compositing a semi-transparent black overlay using an even-odd fill rule.
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - region: The rectangle that remains bright.
    ///   - dimAlpha: Opacity of the dimming overlay (0 = invisible, 1 = fully black).
    /// - Returns: The composited spotlight image, or `nil` on failure.
    static func spotlight(image: CGImage, region: CGRect, dimAlpha: CGFloat = 0.6) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)

        // Draw the original image.
        ctx.draw(image, in: fullRect)

        // Draw a semi-transparent overlay with the spotlight region cut out
        // using the even-odd fill rule.
        ctx.saveGState()
        let path = CGMutablePath()
        path.addRect(fullRect)
        path.addRect(region)
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: dimAlpha))
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        return ctx.makeImage()
    }
}
