import XCTest
@testable import Znap

final class OCRServiceTests: XCTestCase {
    func testRecognizeTextWithBlankImage() async throws {
        // Create a blank white 100x100 image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Failed to create CGContext")
            return
        }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))

        guard let blankImage = ctx.makeImage() else {
            XCTFail("Failed to create CGImage from context")
            return
        }

        // Call recognizeText — should return empty string for blank image
        let result = try await OCRService.shared.recognizeText(in: blankImage)

        // Verify no crash and result is empty
        XCTAssertTrue(result.isEmpty, "Blank image should produce empty OCR result, got: \(result)")
    }
}
