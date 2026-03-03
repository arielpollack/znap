import AppKit
import Carbon

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
    }

    func startAreaCapture() {
        OverlayWindow.beginAreaSelection { rect in
            guard let rect = rect else { return }
            Task {
                do {
                    let cgImage = try await CaptureService.shared.captureArea(rect)
                    let nsImage = NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                    await MainActor.run {
                        QuickAccessOverlay.show(image: nsImage)
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
                let nsImage = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )
                await MainActor.run {
                    QuickAccessOverlay.show(image: nsImage)
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
                    let nsImage = NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                    await MainActor.run {
                        QuickAccessOverlay.show(image: nsImage)
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
                    let nsImage = NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                    await MainActor.run {
                        QuickAccessOverlay.show(image: nsImage)
                    }
                } catch {
                    print("Freeze capture failed: \(error)")
                }
            }
        }
    }
}
