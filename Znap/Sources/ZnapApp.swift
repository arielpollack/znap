import SwiftUI

@main
struct ZnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Znap", systemImage: "camera.viewfinder") {
            Button("Capture Area (\u{2318}\u{21e7}4)") { appDelegate.startAreaCapture() }
            Button("Capture Fullscreen (\u{2318}\u{21e7}3)") { appDelegate.startFullscreenCapture() }
            Button("Capture Window (\u{2318}\u{21e7}5)") { appDelegate.startWindowCapture() }
            Divider()
            Text("Znap v0.1.0").foregroundColor(.secondary)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
