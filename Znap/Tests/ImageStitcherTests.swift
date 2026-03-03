import XCTest
@testable import Znap

final class ImageStitcherTests: XCTestCase {

    /// Helper to create a solid-color CGImage of the given size.
    private func makeImage(
        width: Int,
        height: Int,
        red: CGFloat = 0,
        green: CGFloat = 0,
        blue: CGFloat = 0
    ) -> CGImage? {
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

        ctx.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    func testStitchSingleImage() {
        // Single image should be returned as-is
        guard let image = makeImage(width: 100, height: 50, red: 1) else {
            XCTFail("Failed to create test image")
            return
        }

        let result = ImageStitcher.stitch(images: [image])
        XCTAssertNotNil(result, "Single image stitch should return non-nil")
        XCTAssertEqual(result?.width, 100)
        XCTAssertEqual(result?.height, 50)
    }

    func testStitchEmptyReturnsNil() {
        // Empty array should return nil
        let result = ImageStitcher.stitch(images: [])
        XCTAssertNil(result, "Empty array stitch should return nil")
    }

    func testStitchTwoNonOverlappingImages() {
        // Two different colored images with no overlap should produce combined height
        guard let img1 = makeImage(width: 100, height: 50, red: 1),
              let img2 = makeImage(width: 100, height: 50, blue: 1) else {
            XCTFail("Failed to create test images")
            return
        }

        let result = ImageStitcher.stitch(images: [img1, img2])
        XCTAssertNotNil(result, "Stitched result should be non-nil")
        XCTAssertEqual(result?.width, 100)
        // Without overlap detected, height should be sum of both
        XCTAssertEqual(result?.height, 100)
    }
}
