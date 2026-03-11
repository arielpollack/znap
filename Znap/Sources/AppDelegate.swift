import AppKit
import Carbon
import CoreText
import ScreenCaptureKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    func applicationDidFinishLaunching(_ notification: Notification) {
        registerCustomFonts()
        registerHotkeys()

        NotificationCenter.default.addObserver(
            forName: .hotkeyBindingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reregisterHotkeys()
        }
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
        let prefs = ZnapPreferences()
        let handlers: [CaptureMode: () -> Void] = [
            .allInOne:   { [weak self] in self?.showAllInOne() },
            .area:       { [weak self] in self?.startAreaCapture() },
            .fullscreen: { [weak self] in self?.startFullscreenCapture() },
            .window:     { [weak self] in self?.startWindowCapture() },
            .freeze:     { [weak self] in self?.startFreezeCapture() },
            .ocr:        { [weak self] in self?.startOCRCapture() },
            .scroll:     { [weak self] in self?.startScrollCapture() },
            .record:     { [weak self] in self?.toggleRecording() },
        ]
        for mode in CaptureMode.allCases {
            let binding = prefs.binding(for: mode)
            guard let handler = handlers[mode] else { continue }
            HotkeyService.shared.register(
                keyCode: binding.keyCode,
                modifiers: binding.modifiers,
                handler: handler
            )
        }
    }

    func reregisterHotkeys() {
        HotkeyService.shared.unregisterAll()
        registerHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DesktopIconManager.shared.restoreIfNeeded()
    }

    func showAllInOne() {
        let prefs = ZnapPreferences()
        let modes: [AllInOneHUD.Mode] = [
            AllInOneHUD.Mode(
                id: "area",
                icon: "rectangle.dashed",
                label: "Area",
                shortcut: prefs.binding(for: .area).displayString
            ) { [weak self] in self?.startAreaCapture() },
            AllInOneHUD.Mode(
                id: "window",
                icon: "macwindow",
                label: "Window",
                shortcut: prefs.binding(for: .window).displayString
            ) { [weak self] in self?.startWindowCapture() },
            AllInOneHUD.Mode(
                id: "full",
                icon: "rectangle.fill",
                label: "Full",
                shortcut: prefs.binding(for: .fullscreen).displayString
            ) { [weak self] in self?.startFullscreenCapture() },
            AllInOneHUD.Mode(
                id: "scroll",
                icon: "arrow.up.and.down.text.horizontal",
                label: "Scroll",
                shortcut: prefs.binding(for: .scroll).displayString
            ) { [weak self] in self?.startScrollCapture() },
            AllInOneHUD.Mode(
                id: "record",
                icon: "record.circle",
                label: "Record",
                shortcut: prefs.binding(for: .record).displayString
            ) { [weak self] in self?.toggleRecording() },
            AllInOneHUD.Mode(
                id: "ocr",
                icon: "text.viewfinder",
                label: "OCR",
                shortcut: prefs.binding(for: .ocr).displayString
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

    /// Returns the name of the frontmost application (excluding Znap itself).
    private static func frontmostWindowName() -> String {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return "" }
        return app.localizedName ?? ""
    }

    /// Routes a captured image based on modifier keys held during capture.
    /// - No modifier: Quick Access Overlay (default)
    /// - Option: Save to default save location + toast
    /// - Control: Copy to clipboard + toast
    /// - Shift: Open annotation editor
    private func showCaptureResult(_ nsImage: NSImage, type: String = "area", windowTitle: String = "", modifiers: NSEvent.ModifierFlags = []) {
        HistoryService.shared.addCapture(type: type, image: nsImage)

        if modifiers.contains(.option) {
            // Save directly to default save location
            let prefs = ZnapPreferences()
            let dir = NSString(string: prefs.defaultSaveLocation).expandingTildeInPath
            let filename = "Znap-\(Self.timestampString()).png"
            let url = URL(fileURLWithPath: dir).appendingPathComponent(filename)
            if let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try? data.write(to: url, options: .atomic)
                }
            }
            Task { @MainActor in ToastPanel.show("Saved to \(dir)", icon: "arrow.down.doc") }
        } else if modifiers.contains(.control) {
            // Copy to clipboard as PNG (TIFF not accepted by some apps like WhatsApp)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                if let pngData = bitmap.representation(using: .png, properties: [:]) {
                    pasteboard.setData(pngData, forType: .png)
                }
            }
            Task { @MainActor in ToastPanel.show("Copied to clipboard", icon: "doc.on.clipboard") }
        } else if modifiers.contains(.shift) {
            // Open editor directly
            AnnotationEditorWindow.open(with: nsImage, windowTitle: windowTitle)
        } else if UserDefaults.standard.bool(forKey: "autoOpenEditor") {
            AnnotationEditorWindow.open(with: nsImage, windowTitle: windowTitle)
        } else {
            QuickAccessOverlay.show(image: nsImage, windowTitle: windowTitle)
        }
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    /// Wraps a capture operation with desktop icon hide/restore if enabled.
    private func withDesktopIconsHidden(_ operation: @escaping () -> Void) {
        let prefs = ZnapPreferences()
        guard prefs.autoHideDesktopIcons, !DesktopIconManager.shared.iconsHidden else {
            operation()
            return
        }
        DesktopIconManager.shared.hideIcons()
        // Finder restart takes ~0.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            operation()
        }
    }

    /// Restores desktop icons if they were auto-hidden for capture.
    private func restoreDesktopIconsIfNeeded() {
        if ZnapPreferences().autoHideDesktopIcons {
            DesktopIconManager.shared.restoreIfNeeded()
        }
    }

    func startAreaCapture() {
        let windowTitle = Self.frontmostWindowName()
        withDesktopIconsHidden {
            OverlayWindow.beginAreaSelection { rect in
                self.restoreDesktopIconsIfNeeded()
                guard let rect = rect else { return }
                let modifiers = NSEvent.modifierFlags
                Task {
                    do {
                        let cgImage = try await CaptureService.shared.captureArea(rect)
                        let nsImage = Self.nsImage(from: cgImage)
                        await MainActor.run {
                            self.showCaptureResult(nsImage, windowTitle: windowTitle, modifiers: modifiers)
                        }
                    } catch {
                        print("Capture failed: \(error)")
                    }
                }
            }
        }
    }

    func startFullscreenCapture() {
        let windowTitle = Self.frontmostWindowName()
        let modifiers = NSEvent.modifierFlags
        withDesktopIconsHidden {
            Task {
                do {
                    let cgImage = try await CaptureService.shared.captureFullscreen()
                    let nsImage = Self.nsImage(from: cgImage)
                    await MainActor.run {
                        self.restoreDesktopIconsIfNeeded()
                        self.showCaptureResult(nsImage, type: "fullscreen", windowTitle: windowTitle, modifiers: modifiers)
                    }
                } catch {
                    print("Capture failed: \(error)")
                }
            }
        }
    }

    func startWindowCapture() {
        let windowTitle = Self.frontmostWindowName()
        withDesktopIconsHidden {
            WindowHighlightOverlay.beginWindowSelection { windowID in
                self.restoreDesktopIconsIfNeeded()
                guard let windowID = windowID else { return }
                let modifiers = NSEvent.modifierFlags
                Task {
                    do {
                        let cgImage = try await CaptureService.shared.captureWindow(windowID)
                        let nsImage = Self.nsImage(from: cgImage)
                        await MainActor.run {
                            self.showCaptureResult(nsImage, type: "window", windowTitle: windowTitle, modifiers: modifiers)
                        }
                    } catch {
                        print("Window capture failed: \(error)")
                    }
                }
            }
        }
    }

    func startFreezeCapture() {
        let windowTitle = Self.frontmostWindowName()
        withDesktopIconsHidden {
            FreezeScreenOverlay.beginFrozenCapture { rect in
                self.restoreDesktopIconsIfNeeded()
                guard let rect = rect else { return }
                let modifiers = NSEvent.modifierFlags
                Task {
                    do {
                        let cgImage = try await CaptureService.shared.captureArea(rect)
                        let nsImage = Self.nsImage(from: cgImage)
                        await MainActor.run {
                            self.showCaptureResult(nsImage, type: "freeze", windowTitle: windowTitle, modifiers: modifiers)
                        }
                    } catch {
                        print("Freeze capture failed: \(error)")
                    }
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

                        // Show toast feedback
                        if text.isEmpty {
                            ToastPanel.show("No text found", icon: "text.magnifyingglass")
                        } else {
                            ToastPanel.show("Copied to clipboard", icon: "doc.on.clipboard")
                        }
                    }
                } catch {
                    print("OCR capture failed: \(error)")
                }
            }
        }
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
        Task { @MainActor in
            let service = RecordingService.shared
            if service.isRecording {
                RecordingIndicatorPanel.dismiss()
                if let url = await service.stopRecording() {
                    VideoEditorPanel.show(videoURL: url)
                }
            } else {
                OverlayWindow.beginAreaSelection { rect in
                    guard let rect = rect else { return }
                    Task { @MainActor in
                        do {
                            RecordingIndicatorPanel.show()
                            let excludeIDs = [RecordingIndicatorPanel.windowID].filter { $0 != 0 }
                            let config = RecordingService.RecordingConfig(rect: rect)
                            try await RecordingService.shared.startRecording(
                                config: config,
                                excludeWindowIDs: excludeIDs
                            )
                        } catch {
                            RecordingIndicatorPanel.dismiss()
                            print("Recording failed to start: \(error)")
                        }
                    }
                }
            }
        }
    }
}
