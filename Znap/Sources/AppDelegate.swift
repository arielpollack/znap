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
}
