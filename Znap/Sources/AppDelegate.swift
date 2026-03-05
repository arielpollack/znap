import AppKit
import AVFoundation
import Carbon
import CoreText
import ScreenCaptureKit
import Sparkle
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    func applicationDidFinishLaunching(_ notification: Notification) {
        registerCustomFonts()
        registerHotkeys()
    }

    private func registerCustomFonts() {
        if let url = Bundle.main.url(forResource: "IndieFlower-Regular", withExtension: "ttf") {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                print("Failed to register IndieFlower font: \(String(describing: error?.takeRetainedValue()))")
            }
        }
    }

    private func registerHotkeys() {
        // Cmd+Shift+4 for area capture (kVK_ANSI_4)
        HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_4),
            modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey),
            handler: { [weak self] in self?.startAreaCapture() }
        )

        // Cmd+Shift+3 for fullscreen (kVK_ANSI_3)
        HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_3),
            modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey),
            handler: { [weak self] in self?.startFullscreenCapture() }
        )

        // Cmd+Shift+8 for window capture (kVK_ANSI_8)
        // Note: Cmd+Shift+5 is reserved by macOS for the screenshot utility.
        HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_8),
            modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey),
            handler: { [weak self] in self?.startWindowCapture() }
        )

        // Cmd+Shift+6 for freeze & capture (kVK_ANSI_6)
        HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_6),
            modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey),
            handler: { [weak self] in self?.startFreezeCapture() }
        )

        // Cmd+Shift+R for recording toggle (kVK_ANSI_R)
        HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey),
            handler: { [weak self] in self?.toggleRecording() }
        )

        // Cmd+Shift+2 for OCR text recognition (kVK_ANSI_2)
        HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_2),
            modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey),
            handler: { [weak self] in self?.startOCRCapture() }
        )

        // Cmd+Shift+7 for scrolling capture (kVK_ANSI_7)
        HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_7),
            modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey),
            handler: { [weak self] in self?.startScrollCapture() }
        )

        // Cmd+Shift+P for toggle all pinned screenshots (kVK_ANSI_P)
        HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey),
            handler: { PinnedScreenshotPanel.toggleAllVisibility() }
        )

        // Cmd+Shift+1 for All-In-One HUD (kVK_ANSI_1)
        HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey),
            handler: { [weak self] in self?.showAllInOne() }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        DesktopIconManager.shared.restoreIfNeeded()
    }

    func showAllInOne() {
        let modes: [AllInOneHUD.Mode] = [
            AllInOneHUD.Mode(
                id: "area",
                icon: "rectangle.dashed",
                label: "Area",
                shortcut: "\u{2318}\u{21e7}4"
            ) { [weak self] in self?.startAreaCapture() },
            AllInOneHUD.Mode(
                id: "window",
                icon: "macwindow",
                label: "Window",
                shortcut: "\u{2318}\u{21e7}8"
            ) { [weak self] in self?.startWindowCapture() },
            AllInOneHUD.Mode(
                id: "full",
                icon: "rectangle.fill",
                label: "Full",
                shortcut: "\u{2318}\u{21e7}3"
            ) { [weak self] in self?.startFullscreenCapture() },
            AllInOneHUD.Mode(
                id: "scroll",
                icon: "arrow.up.and.down.text.horizontal",
                label: "Scroll",
                shortcut: "\u{2318}\u{21e7}7"
            ) { [weak self] in self?.startScrollCapture() },
            AllInOneHUD.Mode(
                id: "record",
                icon: "record.circle",
                label: "Record",
                shortcut: "\u{2318}\u{21e7}R"
            ) { [weak self] in self?.toggleRecording() },
            AllInOneHUD.Mode(
                id: "ocr",
                icon: "text.viewfinder",
                label: "OCR",
                shortcut: "\u{2318}\u{21e7}2"
            ) { [weak self] in self?.startOCRCapture() },
        ]
        AllInOneHUD.show(with: modes)
    }

    /// Creates an NSImage from a CGImage with point dimensions for 1:1 Retina display.
    ///
    /// Sets NSImage.size to point dimensions (pixels / backingScaleFactor) so that
    /// each image pixel maps to exactly one screen pixel on Retina displays.
    private static func nsImage(from cgImage: CGImage) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: CGFloat(cgImage.width) / scale,
                height: CGFloat(cgImage.height) / scale
            )
        )
    }

    /// Returns the owner name of the frontmost on-screen window that doesn't
    /// belong to Znap. Falls back to an empty string.
    private static func frontmostWindowName() -> String {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return "" }

        for entry in windowList {
            guard let pid = entry[kCGWindowOwnerPID] as? Int32,
                  pid != ownPID,
                  let name = entry[kCGWindowOwnerName] as? String,
                  let boundsDict = entry[kCGWindowBounds] as? [String: CGFloat],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"],
                  width > 10, height > 10
            else { continue }
            return name
        }
        return ""
    }

    /// Shows the captured image — either in the annotation editor (if autoOpenEditor
    /// is enabled) or in the Quick Access Overlay thumbnail.
    private func showCaptureResult(_ nsImage: NSImage, type: String = "area", windowTitle: String = "") {
        HistoryService.shared.addCapture(type: type, image: nsImage)
        if UserDefaults.standard.bool(forKey: "autoOpenEditor") {
            AnnotationEditorWindow.open(with: nsImage)
        } else {
            QuickAccessOverlay.show(image: nsImage)
        }
    }

    func startAreaCapture() {
        let windowTitle = Self.frontmostWindowName()
        OverlayWindow.beginAreaSelection { rect in
            guard let rect = rect else { return }
            Task {
                do {
                    let cgImage = try await CaptureService.shared.captureArea(rect)
                    let nsImage = Self.nsImage(from: cgImage)
                    await MainActor.run {
                        self.showCaptureResult(nsImage, windowTitle: windowTitle)
                    }
                } catch {
                    print("Capture failed: \(error)")
                }
            }
        }
    }

    func startFullscreenCapture() {
        let windowTitle = Self.frontmostWindowName()
        Task {
            do {
                let cgImage = try await CaptureService.shared.captureFullscreen()
                let nsImage = Self.nsImage(from: cgImage)
                await MainActor.run {
                    self.showCaptureResult(nsImage, type: "fullscreen", windowTitle: windowTitle)
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }

    func startWindowCapture() {
        let windowTitle = Self.frontmostWindowName()
        WindowHighlightOverlay.beginWindowSelection { windowID in
            guard let windowID = windowID else { return }
            Task {
                do {
                    let cgImage = try await CaptureService.shared.captureWindow(windowID)
                    let nsImage = Self.nsImage(from: cgImage)
                    await MainActor.run {
                        self.showCaptureResult(nsImage, type: "window", windowTitle: windowTitle)
                    }
                } catch {
                    print("Window capture failed: \(error)")
                }
            }
        }
    }

    func startFreezeCapture() {
        let windowTitle = Self.frontmostWindowName()
        FreezeScreenOverlay.beginFrozenCapture { rect in
            guard let rect = rect else { return }
            Task {
                do {
                    let cgImage = try await CaptureService.shared.captureArea(rect)
                    let nsImage = Self.nsImage(from: cgImage)
                    await MainActor.run {
                        self.showCaptureResult(nsImage, type: "freeze", windowTitle: windowTitle)
                    }
                } catch {
                    print("Freeze capture failed: \(error)")
                }
            }
        }
    }

    func startOCRCapture() {
        OverlayWindow.beginAreaSelection { rect in
            guard let rect = rect else { return }
            Task {
                do {
                    let cgImage = try await CaptureService.shared.captureArea(rect)
                    let text = try await OCRService.shared.recognizeText(in: cgImage)

                    await MainActor.run {
                        // Copy recognized text to clipboard
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(text, forType: .string)

                        // Show notification
                        self.showOCRNotification(text: text)
                    }
                } catch {
                    print("OCR capture failed: \(error)")
                }
            }
        }
    }

    private func showOCRNotification(text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Znap OCR"
        if text.isEmpty {
            content.body = "No text found in selection."
        } else {
            let preview = text.prefix(100)
            content.body = "Copied to clipboard: \(preview)\(text.count > 100 ? "..." : "")"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func startScrollCapture() {
        let windowTitle = Self.frontmostWindowName()
        OverlayWindow.beginAreaSelection { [weak self] rect in
            guard let self, let rect else { return }

            // Show the blinking overlay.
            ScrollCaptureOverlay.show(around: rect, onStop: { [weak self] in
                guard let self else { return }
                // ENTER pressed — stop capturing and show the stitched result.
                if let cgImage = ScrollCaptureService.shared.stopCapturing() {
                    let nsImage = Self.nsImage(from: cgImage)
                    self.showCaptureResult(nsImage, type: "scroll", windowTitle: windowTitle)
                }
            }, onCancel: {
                // ESC pressed — stop and discard.
                ScrollCaptureService.shared.stopCapturing()
            })

            // Start periodic frame capture.
            ScrollCaptureService.shared.startCapturing(in: rect)
        }
    }

    func toggleRecording() {
        let windowTitle = Self.frontmostWindowName()
        Task { @MainActor in
            let service = RecordingService.shared
            if service.isRecording {
                // Stop the current recording and show result
                if let url = await service.stopRecording() {
                    // Create a thumbnail from the first frame of the video
                    let asset = AVURLAsset(url: url)
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true

                    if let cgImage = try? generator.copyCGImage(
                        at: .zero,
                        actualTime: nil
                    ) {
                        let thumbnail = Self.nsImage(from: cgImage)
                        self.showCaptureResult(thumbnail, type: "recording", windowTitle: windowTitle)
                    }
                }
            } else {
                // Show area selection overlay, then start recording
                OverlayWindow.beginAreaSelection { rect in
                    guard let rect = rect else { return }
                    Task { @MainActor in
                        do {
                            let config = RecordingService.RecordingConfig(rect: rect)
                            try await RecordingService.shared.startRecording(config: config)
                        } catch {
                            print("Recording failed to start: \(error)")
                        }
                    }
                }
            }
        }
    }
}
