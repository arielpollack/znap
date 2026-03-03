import XCTest
@testable import Znap

final class GIFEncoderTests: XCTestCase {
    func testEncodeCreatesValidGIF() throws {
        // Create 3 simple 10x10 colored frames
        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (1, 0, 0),   // red
            (0, 1, 0),   // green
            (0, 0, 1)    // blue
        ]

        var frames: [CGImage] = []
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for (r, g, b) in colors {
            guard let ctx = CGContext(
                data: nil,
                width: 10,
                height: 10,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                XCTFail("Failed to create CGContext")
                return
            }

            ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))

            guard let image = ctx.makeImage() else {
                XCTFail("Failed to create CGImage from context")
                return
            }
            frames.append(image)
        }

        // Encode to a temp file
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).gif")

        let success = GIFEncoder.encode(frames: frames, frameDelay: 0.1, outputURL: outputURL)
        XCTAssertTrue(success, "GIFEncoder.encode should return true")

        // Verify file exists and is non-empty
        let fileExists = FileManager.default.fileExists(atPath: outputURL.path)
        XCTAssertTrue(fileExists, "GIF file should exist at output URL")

        let data = try Data(contentsOf: outputURL)
        XCTAssertFalse(data.isEmpty, "GIF file should not be empty")

        // Verify GIF magic bytes: "GIF" (0x47 0x49 0x46)
        XCTAssertGreaterThanOrEqual(data.count, 3, "GIF file must be at least 3 bytes")
        XCTAssertEqual(data[0], 0x47, "First byte should be 'G'")
        XCTAssertEqual(data[1], 0x49, "Second byte should be 'I'")
        XCTAssertEqual(data[2], 0x46, "Third byte should be 'F'")

        // Clean up
        try FileManager.default.removeItem(at: outputURL)
    }
}
