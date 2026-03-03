import AppKit
import AVFoundation
import Carbon
import ScreenCaptureKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        registerHotkeys()
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

        // Cmd+Shift+5 for window capture (kVK_ANSI_5)
        HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_5),
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
                shortcut: "\u{2318}\u{21e7}5"
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

    /// Shows the captured image — either in the annotation editor (if autoOpenEditor
    /// is enabled) or in the Quick Access Overlay thumbnail.
    private func showCaptureResult(_ nsImage: NSImage) {
        if UserDefaults.standard.bool(forKey: "autoOpenEditor") {
            AnnotationEditorWindow.open(with: nsImage)
        } else {
            QuickAccessOverlay.show(image: nsImage)
        }
    }

    func startAreaCapture() {
        OverlayWindow.beginAreaSelection { rect in
            guard let rect = rect else { return }
            Task {
                do {
                    let cgImage = try await CaptureService.shared.captureArea(rect)
                    let nsImage = Self.nsImage(from: cgImage)
                    await MainActor.run {
                        self.showCaptureResult(nsImage)
                    }
                } catch {
                    print("Capture failed: \(error)")
                }
            }
        }
    }

    func startFullscreenCapture() {
        Task {
            do {
                let cgImage = try await CaptureService.shared.captureFullscreen()
                let nsImage = NSImage(cgImage: cgImage, size: .zero)
                nsImage.size = NSSize(width: cgImage.width, height: cgImage.height)
                await MainActor.run {
                    self.showCaptureResult(nsImage)
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }

    func startWindowCapture() {
        WindowHighlightOverlay.beginWindowSelection { windowID in
            guard let windowID = windowID else { return }
            Task {
                do {
                    let cgImage = try await CaptureService.shared.captureWindow(windowID)
                    let nsImage = Self.nsImage(from: cgImage)
                    await MainActor.run {
                        self.showCaptureResult(nsImage)
                    }
                } catch {
                    print("Window capture failed: \(error)")
                }
            }
        }
    }

    func startFreezeCapture() {
        FreezeScreenOverlay.beginFrozenCapture { rect in
            guard let rect = rect else { return }
            Task {
                do {
                    let cgImage = try await CaptureService.shared.captureArea(rect)
                    let nsImage = Self.nsImage(from: cgImage)
                    await MainActor.run {
                        self.showCaptureResult(nsImage)
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
        OverlayWindow.beginAreaSelection { rect in
            guard let rect = rect else { return }
            Task {
                do {
                    let cgImage = try await ScrollCaptureService.shared.captureScrolling(in: rect)
                    let nsImage = Self.nsImage(from: cgImage)
                    await MainActor.run {
                        self.showCaptureResult(nsImage)
                    }
                } catch {
                    print("Scroll capture failed: \(error)")
                }
            }
        }
    }

    func toggleRecording() {
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
                        self.showCaptureResult(thumbnail)
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
