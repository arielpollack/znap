import Foundation

/// Manages the visibility of desktop icons by toggling the Finder's
/// `CreateDesktop` preference.
///
/// Desktop icons can be hidden before captures to produce cleaner screenshots.
/// The ``restoreIfNeeded()`` method should be called in `applicationWillTerminate`
/// to ensure icons are always restored when the app quits.
///
/// ## Usage
///
/// ```swift
/// DesktopIconManager.shared.hideIcons()
/// // ... capture screenshot ...
/// DesktopIconManager.shared.showIcons()
/// ```
final class DesktopIconManager {
    static let shared = DesktopIconManager()

    /// Whether icons were hidden by this manager and need restoring.
    private var didHideIcons = false

    private init() {}

    // MARK: - Public API

    /// Hides desktop icons by disabling the Finder's CreateDesktop preference.
    ///
    /// Sets `com.apple.finder CreateDesktop` to `false` and restarts Finder.
    func hideIcons() {
        setCreateDesktop(false)
        didHideIcons = true
        restartFinder()
    }

    /// Shows desktop icons by enabling the Finder's CreateDesktop preference.
    ///
    /// Sets `com.apple.finder CreateDesktop` to `true` and restarts Finder.
    func showIcons() {
        setCreateDesktop(true)
        didHideIcons = false
        restartFinder()
    }

    /// Restores desktop icons if they were hidden by this manager.
    ///
    /// This is a safety net — call it from `applicationWillTerminate(_:)` to
    /// ensure the user's desktop is always restored.
    func restoreIfNeeded() {
        guard didHideIcons else { return }
        showIcons()
    }

    /// Returns `true` if desktop icons are currently hidden by this manager.
    var iconsHidden: Bool {
        didHideIcons
    }

    // MARK: - Private Helpers

    /// Sets the Finder's `CreateDesktop` default to the given boolean value.
    private func setCreateDesktop(_ value: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = [
            "write", "com.apple.finder",
            "CreateDesktop", "-bool", value ? "true" : "false"
        ]
        try? process.run()
        process.waitUntilExit()
    }

    /// Restarts the Finder so the `CreateDesktop` change takes effect.
    private func restartFinder() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
        process.waitUntilExit()
    }
}
