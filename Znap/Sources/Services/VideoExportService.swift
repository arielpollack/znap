import AVFoundation

/// Service for re-exporting edited recordings using `AVMutableComposition`.
///
/// Supports:
/// - Trimming (selecting specific time ranges)
/// - Deleting segments
/// - Speed changes per segment
///
/// Output is written as H.264 MP4 to the user's Desktop.
enum VideoExportService {

    // MARK: - Types

    /// Describes a contiguous slice of the source video.
    struct Segment {
        /// Start time in the source video, in seconds.
        var startTime: Double
        /// End time in the source video, in seconds.
        var endTime: Double
        /// Playback speed multiplier (1.0 = normal, 2.0 = 2x fast, 0.5 = half speed).
        var speed: Double = 1.0
        /// Whether this segment should be excluded from export.
        var deleted: Bool = false
    }

    /// Errors that can occur during export.
    enum ExportError: Error, LocalizedError {
        case noVideoTrack
        case exportFailed(String)
        case exportCancelled

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                return "Source video contains no video track."
            case .exportFailed(let reason):
                return "Export failed: \(reason)"
            case .exportCancelled:
                return "Export was cancelled."
            }
        }
    }

    // MARK: - Public API

    /// Export the source video with the given segment edits applied.
    ///
    /// Each non-deleted segment is inserted into an `AVMutableComposition` in order.
    /// Segments with `speed != 1.0` are time-scaled accordingly.
    ///
    /// - Parameters:
    ///   - source: URL of the source MP4 file.
    ///   - segments: Ordered list of segments describing the edit.
    /// - Returns: URL of the exported MP4 on the Desktop.
    static func export(source: URL, segments: [Segment]) async throws -> URL {
        let asset = AVURLAsset(url: source)

        // Load source tracks
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw ExportError.noVideoTrack
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let sourceAudioTrack = audioTracks.first

        // Build composition
        let composition = AVMutableComposition()

        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.exportFailed("Failed to create composition video track.")
        }

        var compAudioTrack: AVMutableCompositionTrack?
        if sourceAudioTrack != nil {
            compAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }

        // Insert each non-deleted segment
        var insertionTime = CMTime.zero

        for segment in segments where !segment.deleted {
            let startCMTime = CMTime(seconds: segment.startTime, preferredTimescale: 600)
            let endCMTime = CMTime(seconds: segment.endTime, preferredTimescale: 600)
            let duration = endCMTime - startCMTime
            let sourceRange = CMTimeRange(start: startCMTime, duration: duration)

            // Insert video
            try compVideoTrack.insertTimeRange(sourceRange, of: sourceVideoTrack, at: insertionTime)

            // Insert audio (if present)
            if let srcAudio = sourceAudioTrack, let compAudio = compAudioTrack {
                try compAudio.insertTimeRange(sourceRange, of: srcAudio, at: insertionTime)
            }

            // Apply speed change
            if segment.speed != 1.0 {
                let scaledDuration = CMTime(
                    seconds: duration.seconds / segment.speed,
                    preferredTimescale: 600
                )
                let insertedRange = CMTimeRange(start: insertionTime, duration: duration)

                compVideoTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                compAudioTrack?.scaleTimeRange(insertedRange, toDuration: scaledDuration)

                insertionTime = insertionTime + scaledDuration
            } else {
                insertionTime = insertionTime + duration
            }
        }

        // Output URL on Desktop
        let outputURL = desktopOutputURL()

        // Export
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportFailed("Could not create export session.")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return outputURL
        case .cancelled:
            throw ExportError.exportCancelled
        case .failed:
            let message = exportSession.error?.localizedDescription ?? "Unknown error"
            throw ExportError.exportFailed(message)
        default:
            throw ExportError.exportFailed("Unexpected export status: \(exportSession.status.rawValue)")
        }
    }

    // MARK: - Private Helpers

    /// Generates a Desktop file URL with a timestamped name.
    private static func desktopOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "Znap-\(timestamp).mp4"

        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktopURL.appendingPathComponent(fileName)
    }
}
