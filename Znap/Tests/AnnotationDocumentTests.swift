import XCTest
@testable import Znap

final class AnnotationDocumentTests: XCTestCase {

    // MARK: - Codable Round-Trip

    /// Encodes an ``AnnotationDocument`` to JSON and decodes it back, verifying
    /// that every field survives the round-trip intact.
    func testCodableRoundTrip() throws {
        let fakeImageData = Data(repeating: 0xFF, count: 64)

        let annotations: [AnnotationDocument.Annotation] = [
            AnnotationDocument.Annotation(
                id: UUID(),
                type: .arrow,
                startPoint: CGPoint(x: 10, y: 20),
                endPoint: CGPoint(x: 100, y: 200),
                points: nil,
                color: .defaultRed,
                strokeWidth: 3,
                text: nil,
                fontSize: nil,
                counterValue: nil,
                isFilled: false
            ),
            AnnotationDocument.Annotation(
                id: UUID(),
                type: .pencil,
                startPoint: CGPoint(x: 5, y: 5),
                endPoint: CGPoint(x: 50, y: 50),
                points: [
                    CGPoint(x: 5, y: 5),
                    CGPoint(x: 25, y: 30),
                    CGPoint(x: 50, y: 50),
                ],
                color: AnnotationDocument.CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                strokeWidth: 2,
                text: nil,
                fontSize: nil,
                counterValue: nil,
                isFilled: false
            ),
            AnnotationDocument.Annotation(
                id: UUID(),
                type: .counter,
                startPoint: CGPoint(x: 60, y: 60),
                endPoint: CGPoint(x: 60, y: 60),
                points: nil,
                color: .defaultRed,
                strokeWidth: 1,
                text: nil,
                fontSize: 14,
                counterValue: 3,
                isFilled: true
            ),
            AnnotationDocument.Annotation(
                id: UUID(),
                type: .text,
                startPoint: CGPoint(x: 70, y: 80),
                endPoint: CGPoint(x: 200, y: 100),
                points: nil,
                color: AnnotationDocument.CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                strokeWidth: 1,
                text: "Hello, World!",
                fontSize: 16,
                counterValue: nil,
                isFilled: false
            ),
        ]

        let original = AnnotationDocument(
            imageData: fakeImageData,
            annotations: annotations,
            canvasSize: CGSize(width: 1024, height: 768)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnnotationDocument.self, from: data)

        // Image data
        XCTAssertEqual(decoded.imageData, original.imageData)

        // Canvas size
        XCTAssertEqual(decoded.canvasSize.width, 1024)
        XCTAssertEqual(decoded.canvasSize.height, 768)

        // Annotation count
        XCTAssertEqual(decoded.annotations.count, 4)

        // Arrow annotation
        let arrow = decoded.annotations[0]
        XCTAssertEqual(arrow.type, .arrow)
        XCTAssertEqual(arrow.startPoint.x, 10)
        XCTAssertEqual(arrow.startPoint.y, 20)
        XCTAssertEqual(arrow.endPoint.x, 100)
        XCTAssertEqual(arrow.endPoint.y, 200)
        XCTAssertNil(arrow.points)
        XCTAssertEqual(arrow.color, .defaultRed)
        XCTAssertEqual(arrow.strokeWidth, 3)
        XCTAssertFalse(arrow.isFilled)

        // Pencil annotation with freehand points
        let pencil = decoded.annotations[1]
        XCTAssertEqual(pencil.type, .pencil)
        XCTAssertEqual(pencil.points?.count, 3)
        XCTAssertEqual(pencil.points?[1].x, 25)
        XCTAssertEqual(pencil.color.blue, 1)

        // Counter annotation
        let counter = decoded.annotations[2]
        XCTAssertEqual(counter.type, .counter)
        XCTAssertEqual(counter.counterValue, 3)
        XCTAssertTrue(counter.isFilled)
        XCTAssertEqual(counter.fontSize, 14)

        // Text annotation
        let textAnnotation = decoded.annotations[3]
        XCTAssertEqual(textAnnotation.type, .text)
        XCTAssertEqual(textAnnotation.text, "Hello, World!")
        XCTAssertEqual(textAnnotation.fontSize, 16)
    }

    // MARK: - Empty Annotations

    /// A document with no annotations should round-trip cleanly.
    func testEmptyAnnotationsRoundTrip() throws {
        let doc = AnnotationDocument(
            imageData: Data([0x01, 0x02]),
            canvasSize: CGSize(width: 100, height: 50)
        )

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: data)

        XCTAssertEqual(decoded.annotations.count, 0)
        XCTAssertEqual(decoded.imageData, doc.imageData)
    }

    // MARK: - CodableColor

    /// Verify the default red constant has expected component values.
    func testDefaultRedColor() {
        let c = AnnotationDocument.CodableColor.defaultRed
        XCTAssertEqual(c.red, 1)
        XCTAssertEqual(c.green, 0.23)
        XCTAssertEqual(c.blue, 0.19)
        XCTAssertEqual(c.alpha, 1)
    }

    // MARK: - All Annotation Types

    /// Make sure every ``AnnotationType`` case encodes & decodes.
    func testAllAnnotationTypesRoundTrip() throws {
        for annotationType in AnnotationDocument.AnnotationType.allCases {
            let annotation = AnnotationDocument.Annotation(
                id: UUID(),
                type: annotationType,
                startPoint: .zero,
                endPoint: CGPoint(x: 1, y: 1),
                points: nil,
                color: .defaultRed,
                strokeWidth: 1,
                text: nil,
                fontSize: nil,
                counterValue: nil,
                isFilled: false
            )

            let doc = AnnotationDocument(
                imageData: Data(),
                annotations: [annotation],
                canvasSize: CGSize(width: 1, height: 1)
            )

            let data = try JSONEncoder().encode(doc)
            let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: data)

            XCTAssertEqual(
                decoded.annotations.first?.type,
                annotationType,
                "Round-trip failed for annotation type: \(annotationType.rawValue)"
            )
        }
    }
}
