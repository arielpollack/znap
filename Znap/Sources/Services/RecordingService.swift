import AVFoundation
import ScreenCaptureKit
import Combine

/// Service that wraps ScreenCaptureKit's `SCStream` for video screen recording.
///
/// Supports:
/// - Area recording (region of a display)
/// - Fullscreen recording
/// - Window recording
/// - Optional audio capture (system audio and/or microphone)
/// - Pause/resume
/// - Elapsed time tracking
///
/// Output is written as H.264 MP4 to a temporary file.
@MainActor
final class RecordingService: NSObject, ObservableObject {
    static let shared = RecordingService()

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var elapsedTime: TimeInterval = 0

    struct RecordingConfig {
        var rect: CGRect?                       // nil = fullscreen
        var windowID: CGWindowID?               // nil = not window-specific
        var displayID: CGDirectDisplayID?
        var fps: Int = 30
        var captureAudio: Bool = false
        var captureMic: Bool = false
        var showCursor: Bool = true
        var outputAsGIF: Bool = false
    }

    enum RecordingError: Error {
        case noDisplay
        case alreadyRecording
        case notRecording
        case assetWriterFailed(String)
        case streamFailed(String)
    }

    // MARK: - Private State

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var streamOutput: StreamOutputHandler?
    private var elapsedTimer: Timer?
    private var recordingStartDate: Date?
    private var currentConfig: RecordingConfig?

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Start recording the screen with the given configuration.
    ///
    /// - Parameter config: Describes what to record (area, window, display) and how (FPS, audio, etc.).
    func startRecording(config: RecordingConfig) async throws {
        guard !isRecording else {
            throw RecordingError.alreadyRecording
        }

        currentConfig = config

        // 1. Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        // 2. Determine the display
        let display: SCDisplay
        if let displayID = config.displayID,
           let found = content.displays.first(where: { $0.displayID == displayID }) {
            display = found
        } else if let rect = config.rect,
                  let found = content.displays.first(where: { $0.frame.contains(rect.origin) }) {
            display = found
        } else if let first = content.displays.first {
            display = first
        } else {
            throw RecordingError.noDisplay
        }

        let scaleFactor = CaptureService.scaleFactor(for: display)

        // 3. Create content filter
        let filter: SCContentFilter
        if let windowID = config.windowID,
           let window = content.windows.first(where: { $0.windowID == windowID }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        // 4. Configure stream
        let streamConfig = SCStreamConfiguration()

        if let rect = config.rect {
            // Area recording: set sourceRect with Retina scaling
            streamConfig.sourceRect = CGRect(
                x: rect.origin.x * scaleFactor,
                y: rect.origin.y * scaleFactor,
                width: rect.width * scaleFactor,
                height: rect.height * scaleFactor
            )
            streamConfig.width = Int(rect.width * scaleFactor)
            streamConfig.height = Int(rect.height * scaleFactor)
        } else {
            streamConfig.width = display.width
            streamConfig.height = display.height
        }

        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        streamConfig.showsCursor = config.showCursor
        streamConfig.capturesAudio = config.captureAudio

        let pixelWidth = streamConfig.width
        let pixelHeight = streamConfig.height

        // 5. Set up AVAssetWriter
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "znap_recording_\(Int(Date().timeIntervalSince1970)).mp4"
        let fileURL = tempDir.appendingPathComponent(fileName)
        outputURL = fileURL

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
        } catch {
            throw RecordingError.assetWriterFailed(error.localizedDescription)
        }

        // Video input: H.264
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        writer.add(vInput)
        videoInput = vInput

        // Audio input: AAC (optional)
        if config.captureAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            writer.add(aInput)
            audioInput = aInput
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        assetWriter = writer

        // 6. Create stream output handler
        let handler = StreamOutputHandler(service: self)
        streamOutput = handler

        // 7. Create and start SCStream
        let scStream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        try scStream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.znap.recording.video"))

        if config.captureAudio {
            try scStream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.znap.recording.audio"))
        }

        try await scStream.startCapture()
        stream = scStream

        // 8. Update state
        isRecording = true
        isPaused = false
        elapsedTime = 0
        recordingStartDate = Date()

        startElapsedTimer()
    }

    /// Stop the current recording and return the URL of the output file.
    ///
    /// - Returns: The URL of the recorded MP4 file, or `nil` if something went wrong.
    func stopRecording() async -> URL? {
        guard isRecording else { return nil }

        stopElapsedTimer()

        // Stop stream capture
        if let stream = stream {
            do {
                try await stream.stopCapture()
            } catch {
                print("RecordingService: failed to stop stream capture: \(error)")
            }
        }
        stream = nil
        streamOutput = nil

        // Finish writing
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        let url = outputURL

        if let writer = assetWriter, writer.status == .writing {
            await writer.finishWriting()
        }

        // Clean up
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        outputURL = nil

        isRecording = false
        isPaused = false
        elapsedTime = 0
        recordingStartDate = nil
        currentConfig = nil

        return url
    }

    /// Toggle pause/resume for the current recording.
    ///
    /// When paused, incoming sample buffers are discarded.
    func togglePause() {
        guard isRecording else { return }
        isPaused.toggle()

        if isPaused {
            stopElapsedTimer()
        } else {
            startElapsedTimer()
        }
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.recordingStartDate, !self.isPaused else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Stream Output Handler

    /// Helper class conforming to `SCStreamOutput` that receives sample buffers from ScreenCaptureKit
    /// and appends them to the AVAssetWriter inputs.
    ///
    /// The `stream(_:didOutputSampleBuffer:of:)` method is called from a non-main queue,
    /// so it is marked `nonisolated`. It dispatches back to the main actor to check
    /// RecordingService state (isPaused, input readiness).
    final class StreamOutputHandler: NSObject, SCStreamOutput {
        private weak var service: RecordingService?
        private var sessionStarted = false
        private var firstSampleTime: CMTime?

        init(service: RecordingService) {
            self.service = service
            super.init()
        }

        nonisolated func stream(
            _ stream: SCStream,
            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
            of type: SCStreamOutputType
        ) {
            guard sampleBuffer.isValid else { return }

            let service = self.service
            Task { @MainActor in
                guard let service = service else { return }
                guard !service.isPaused else { return }
                guard service.assetWriter?.status == .writing else { return }

                switch type {
                case .screen:
                    if let videoInput = service.videoInput, videoInput.isReadyForMoreMediaData {
                        videoInput.append(sampleBuffer)
                    }
                case .audio, .microphone:
                    if let audioInput = service.audioInput, audioInput.isReadyForMoreMediaData {
                        audioInput.append(sampleBuffer)
                    }
                @unknown default:
                    break
                }
            }
        }
    }
}
