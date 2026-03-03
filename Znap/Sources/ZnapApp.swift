import SwiftUI

@main
struct ZnapApp: App {
    var body: some Scene {
        MenuBarExtra("Znap", systemImage: "camera.viewfinder") {
            Text("Znap v0.1.0")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
