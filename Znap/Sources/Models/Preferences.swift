import SwiftUI

/// Observable object that persists user preferences using `@AppStorage`.
///
/// ``ZnapPreferences`` centralises all user-configurable settings so that
/// they can be read from any SwiftUI view or service. Values are automatically
/// saved to `UserDefaults`.
final class ZnapPreferences: ObservableObject {

    // MARK: - General

    /// Default directory for saved screenshots.
    @AppStorage("defaultSaveLocation") var defaultSaveLocation = "~/Desktop"

    /// Whether to launch Znap automatically at login.
    @AppStorage("launchAtLogin") var launchAtLogin = false

    /// Number of days to keep capture history before automatic cleanup.
    @AppStorage("historyRetentionDays") var historyRetentionDays = 30

    // MARK: - Capture

    /// Default image format for saved screenshots.
    @AppStorage("defaultFormat") var defaultFormat = "png"

    /// JPEG compression quality (0.0–1.0), used when `defaultFormat` is `"jpeg"`.
    @AppStorage("jpegQuality") var jpegQuality = 0.85

    /// Auto-dismiss timeout for the Quick Access Overlay, in seconds.
    @AppStorage("qaoAutoDismiss") var qaoAutoDismiss = 15.0

    /// Whether to include the native macOS window shadow in window captures.
    @AppStorage("includeWindowShadow") var includeWindowShadow = true

    /// Whether to automatically hide desktop icons before each capture.
    @AppStorage("autoHideDesktopIcons") var autoHideDesktopIcons = false

    /// Whether to open the annotation editor immediately after capture
    /// instead of showing the Quick Access Overlay thumbnail.
    @AppStorage("autoOpenEditor") var autoOpenEditor = false

    // MARK: - Recording

    /// Frames per second for screen recordings.
    @AppStorage("recordingFPS") var recordingFPS = 30

    /// Output format for screen recordings.
    @AppStorage("recordingFormat") var recordingFormat = "mp4"
}
