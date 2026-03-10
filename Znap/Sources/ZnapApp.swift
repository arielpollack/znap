import SwiftUI

@main
struct ZnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Znap", systemImage: "camera.viewfinder") {
            // All-In-One
            Button("All-In-One (\u{2318}\u{21e7}1)") { appDelegate.showAllInOne() }

            Divider()

            // Capture modes
            Button("Capture Area (\u{2318}\u{21e7}4)") { appDelegate.startAreaCapture() }
            Button("Capture Fullscreen (\u{2318}\u{21e7}3)") { appDelegate.startFullscreenCapture() }
            Button("Capture Window (\u{2318}\u{21e7}8)") { appDelegate.startWindowCapture() }
            Button("Freeze & Capture (\u{2318}\u{21e7}6)") { appDelegate.startFreezeCapture() }

            Divider()

            Button("OCR Text (\u{2318}\u{21e7}2)") { appDelegate.startOCRCapture() }
            Button("Scrolling Capture (\u{2318}\u{21e7}7)") { appDelegate.startScrollCapture() }

            Divider()

            Button("Record Screen (\u{2318}\u{21e7}R)") { appDelegate.toggleRecording() }

            Divider()

            Button("Show Editor") { AnnotationEditorWindow.restore() }

            Divider()

            // Desktop icons toggle
            Button(DesktopIconManager.shared.iconsHidden ? "Show Desktop Icons" : "Hide Desktop Icons") {
                if DesktopIconManager.shared.iconsHidden {
                    DesktopIconManager.shared.showIcons()
                } else {
                    DesktopIconManager.shared.hideIcons()
                }
            }

            Button(UserDefaults.standard.bool(forKey: "includeWindowShadow")
                ? "✓ Window Shadow"
                : "   Window Shadow") {
                let current = UserDefaults.standard.bool(forKey: "includeWindowShadow")
                UserDefaults.standard.set(!current, forKey: "includeWindowShadow")
            }

            Divider()

            // History submenu
            Menu("Recent Captures") {
                let items = HistoryService.shared.recentCaptures(limit: 10)
                if items.isEmpty {
                    Text("No captures yet").foregroundColor(.secondary)
                } else {
                    ForEach(items, id: \.id) { item in
                        Button("\(item.captureType) — \(formattedDate(item.timestamp))") {
                            if let path = item.filePath {
                                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                            }
                        }
                    }
                }
            }

            Divider()

            // Preferences
            Button("Preferences...") {
                PreferencesWindow.show()
            }
            .keyboardShortcut(",")

            Button("Check for Updates...") {
                appDelegate.updaterController.checkForUpdates(nil)
            }

            Divider()

            Text("Znap v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .foregroundColor(.secondary)

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings {
            EmptyView()
        }
    }

    /// Formats a date for display in the history submenu.
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
