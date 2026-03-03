import Vision
import AppKit

/// Service that performs optical character recognition (OCR) on captured screenshots
/// using the Vision framework's text recognition capabilities.
///
/// Supports accurate recognition with language correction and automatic language detection.
///
/// ## Usage
///
/// ```swift
/// let text = try await OCRService.shared.recognizeText(in: cgImage)
/// ```
final class OCRService {
    static let shared = OCRService()

    private init() {}

    enum OCRError: Error {
        case recognitionFailed
    }

    /// Recognizes text in the given image using Vision framework.
    ///
    /// - Parameter image: The `CGImage` to perform text recognition on.
    /// - Returns: A string containing all recognized text, with lines separated by newlines.
    func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
