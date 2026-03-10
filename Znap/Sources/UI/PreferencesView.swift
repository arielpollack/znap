import SwiftUI

/// The main preferences window content, displayed as a `Settings` scene.
///
/// Organised into four tabs:
/// - **General**: Save location, launch at login, history retention.
/// - **Capture**: Image format, quality, overlay timeout, shadows, desktop icons.
/// - **Recording**: FPS and output format.
/// - **Shortcuts**: Per-mode keyboard shortcut customization.
struct PreferencesView: View {
    @StateObject private var prefs = ZnapPreferences()

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            captureTab
                .tabItem { Label("Capture", systemImage: "camera") }
            recordingTab
                .tabItem { Label("Recording", systemImage: "record.circle") }
            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 420, height: 340)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            TextField("Save Location:", text: $prefs.defaultSaveLocation)
                .help("Default directory for saved screenshots.")

            Toggle("Launch at Login", isOn: $prefs.launchAtLogin)

            Stepper(
                "History Retention: \(prefs.historyRetentionDays) days",
                value: $prefs.historyRetentionDays,
                in: 1...365
            )
        }
        .padding()
    }

    // MARK: - Capture Tab

    private var captureTab: some View {
        Form {
            Picker("Default Format:", selection: $prefs.defaultFormat) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpeg")
                Text("TIFF").tag("tiff")
            }

            if prefs.defaultFormat == "jpeg" {
                HStack {
                    Text("JPEG Quality:")
                    Slider(value: $prefs.jpegQuality, in: 0.1...1.0, step: 0.05)
                    Text("\(Int(prefs.jpegQuality * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            HStack {
                Text("Auto-Dismiss Overlay:")
                Slider(value: $prefs.qaoAutoDismiss, in: 5...60, step: 5)
                Text("\(Int(prefs.qaoAutoDismiss))s")
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }

            Toggle("Open Editor After Capture", isOn: $prefs.autoOpenEditor)
                .help("Skip the thumbnail and open the annotation editor immediately.")
            Toggle("Include Window Shadow", isOn: $prefs.includeWindowShadow)
            Toggle("Auto-Hide Desktop Icons", isOn: $prefs.autoHideDesktopIcons)
        }
        .padding()
    }

    // MARK: - Recording Tab

    private var recordingTab: some View {
        Form {
            Stepper("FPS: \(prefs.recordingFPS)", value: $prefs.recordingFPS, in: 15...60, step: 5)

            Picker("Format:", selection: $prefs.recordingFormat) {
                Text("MP4").tag("mp4")
                Text("MOV").tag("mov")
            }

            Stepper("GIF Frame Rate: \(prefs.gifFrameRate) fps", value: $prefs.gifFrameRate, in: 5...15, step: 5)
        }
        .padding()
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        Form {
            ForEach(CaptureMode.allCases, id: \.rawValue) { mode in
                ShortcutRecorderRow(mode: mode)
            }
        }
        .padding()
    }
}

/// A single row in the Shortcuts tab that reads/writes a hotkey binding
/// for a given capture mode and posts a notification on change.
private struct ShortcutRecorderRow: View {
    let mode: CaptureMode
    @State private var binding: HotkeyBinding

    init(mode: CaptureMode) {
        self.mode = mode
        self._binding = State(initialValue: ZnapPreferences().binding(for: mode))
    }

    var body: some View {
        ShortcutRecorderView(mode: mode, binding: $binding)
            .onChange(of: binding) { newValue in
                ZnapPreferences().setBinding(newValue, for: mode)
                NotificationCenter.default.post(name: .hotkeyBindingsChanged, object: nil)
            }
    }
}

extension Notification.Name {
    static let hotkeyBindingsChanged = Notification.Name("HotkeyBindingsChanged")
}
