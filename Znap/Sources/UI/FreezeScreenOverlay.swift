import AppKit

/// A utility that freezes the current screen content and allows the user to
/// select an area from the frozen image.
///
/// The freeze-capture workflow:
/// 1. Immediately captures all connected displays using `CGDisplayCreateImage`.
/// 2. Creates a full-screen window for each display showing the frozen screenshot.
/// 3. Presents the area-selection overlay (``OverlayWindow``) on top of the frozen images.
/// 4. When selection completes (or is cancelled), closes all frozen windows.
///
/// This is useful for capturing UI states that change when the mouse moves or when
/// overlay interactions would otherwise alter the screen content.
///
/// ## Usage
///
/// ```swift
/// FreezeScreenOverlay.beginFrozenCapture { rect in
///     guard let rect else { return }  // user cancelled
///     // rect is in screen coordinates, ready for CaptureService
/// }
/// ```
final class FreezeScreenOverlay {

    /// Begins a frozen-screen capture session.
    ///
    /// Captures all screens, displays frozen images, and shows the area-selection
    /// overlay on top. The completion handler receives the selected rectangle in
    /// screen coordinates, or `nil` if the user cancelled.
    ///
    /// - Parameter completion: Called with the selected `CGRect` or `nil`.
    static func beginFrozenCapture(completion: @escaping (CGRect?) -> Void) {
        var frozenWindows: [NSWindow] = []

        for screen in NSScreen.screens {
            // Extract the CGDirectDisplayID from the screen's device description.
            guard let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID,
                  let cgImage = CGDisplayCreateImage(displayID) else {
                continue
            }

            let nsImage = NSImage(cgImage: cgImage, size: screen.frame.size)

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            // Place frozen windows just below the selection overlay level.
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
            window.isOpaque = true
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false

            let imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            imageView.image = nsImage
            imageView.imageScaling = .scaleAxesIndependently
            imageView.autoresizingMask = [.width, .height]
            window.contentView = imageView
            window.orderFront(nil)

            frozenWindows.append(window)
        }

        // Show the area-selection overlay on top of the frozen screens.
        OverlayWindow.beginAreaSelection { rect in
            // Clean up frozen windows regardless of outcome.
            for window in frozenWindows {
                window.close()
            }
            frozenWindows.removeAll()

            completion(rect)
        }
    }
}
