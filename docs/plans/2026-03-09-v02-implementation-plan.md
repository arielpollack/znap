# Znap v0.2 — Table Stakes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship 6 features that bring Znap to competitive parity with CleanShot X and Shottr.

**Architecture:** Each task is self-contained with a commit boundary. Shared infrastructure (ToastView) is built first, then features build on it. No test suite exists yet so we skip TDD — verify by building and running (`make run`).

**Tech Stack:** Swift, SwiftUI, AppKit, Carbon (hotkeys), AVFoundation, ImageIO, ScreenCaptureKit

---

### Task 1: ToastView — Shared Transient HUD

Reusable toast notification used by Features 4, 5, and 2.

**Files:**
- Create: `Znap/Sources/UI/ToastView.swift`

**Step 1: Create ToastView**

Build a floating NSPanel subclass that shows a brief message and auto-dismisses.

```swift
// ToastView.swift
import AppKit

/// A lightweight, non-activating floating HUD that displays a brief message
/// and fades out automatically.
final class ToastPanel: NSPanel {
    private static var current: ToastPanel?

    private init(message: String, icon: String? = nil) {
        // Size and position: centered horizontally, lower third of screen
        let width: CGFloat = 280
        let height: CGFloat = 44
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screen.midX - width / 2,
            y: screen.minY + screen.height * 0.25
        )
        super.init(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true

        // Visual effect background
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: NSSize(width: width, height: height)))
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = height / 2
        blur.layer?.masksToBounds = true

        // Label
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center

        // Icon (optional)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        if let iconName = icon {
            let imageView = NSImageView()
            imageView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            imageView.contentTintColor = .white
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            stack.addArrangedSubview(imageView)
        }
        stack.addArrangedSubview(label)
        stack.translatesAutoresizingMaskIntoConstraints = false

        blur.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
        ])

        contentView = blur
    }

    /// Shows a toast message that auto-dismisses after the given duration.
    static func show(_ message: String, icon: String? = nil, duration: TimeInterval = 1.5) {
        current?.close()

        let panel = ToastPanel(message: message, icon: icon)
        current = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    panel.animator().alphaValue = 0
                }) {
                    panel.close()
                    if Self.current === panel { Self.current = nil }
                }
            }
        }
    }
}
```

**Step 2: Build and verify**

Run: `make run`
Expected: BUILD SUCCEEDED. Toast not visible yet (no callers).

**Step 3: Commit**

```bash
git add Znap/Sources/UI/ToastView.swift
git commit -m "feat: add ToastPanel reusable transient HUD component"
```

---

### Task 2: Instant OCR Toast (Feature 4)

Replace heavy UNNotification with the new ToastPanel.

**Files:**
- Modify: `Znap/Sources/AppDelegate.swift:231-272`

**Step 1: Replace showOCRNotification with ToastPanel**

In `AppDelegate.swift`, replace the `showOCRNotification` method and its call site:

```swift
// In startOCRCapture(), replace:
//     self.showOCRNotification(text: text)
// With:
if text.isEmpty {
    ToastPanel.show("No text found", icon: "text.magnifyingglass")
} else {
    ToastPanel.show("Copied to clipboard", icon: "doc.on.clipboard")
}
```

Delete the entire `showOCRNotification(_:)` method (lines 255-272).

Remove the `import UserNotifications` if it's no longer used elsewhere.

**Step 2: Build and test**

Run: `make run`
Test: Use Cmd+Shift+2, select some text on screen. Verify:
- Text is copied to clipboard
- A rounded HUD appears briefly saying "Copied to clipboard"
- No system notification popup

**Step 3: Commit**

```bash
git add Znap/Sources/AppDelegate.swift
git commit -m "feat: replace OCR notification with lightweight toast HUD"
```

---

### Task 3: Destination Modifiers (Feature 5)

Detect modifier keys at capture completion to route results differently.

**Files:**
- Modify: `Znap/Sources/AppDelegate.swift:153-160` (showCaptureResult)
- Modify: `Znap/Sources/AppDelegate.swift:162-229` (capture methods)

**Step 1: Update showCaptureResult to accept modifiers**

```swift
/// Routes a captured image based on modifier keys held during capture.
/// - No modifier: Quick Access Overlay (default)
/// - Option: Save to default location + toast
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
        ToastPanel.show("Saved to \(dir)", icon: "arrow.down.doc")
    } else if modifiers.contains(.control) {
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
        ToastPanel.show("Copied to clipboard", icon: "doc.on.clipboard")
    } else if modifiers.contains(.shift) {
        // Open editor directly
        AnnotationEditorWindow.open(with: nsImage, windowTitle: windowTitle)
    } else if UserDefaults.standard.bool(forKey: "autoOpenEditor") {
        AnnotationEditorWindow.open(with: nsImage, windowTitle: windowTitle)
    } else {
        QuickAccessOverlay.show(image: nsImage, windowTitle: windowTitle)
    }
}
```

Add a timestamp helper:

```swift
private static func timestampString() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    return formatter.string(from: Date())
}
```

**Step 2: Pass modifier flags from capture methods**

For area/freeze captures (which use mouse-up), read `NSEvent.modifierFlags` at the completion callback:

```swift
func startAreaCapture() {
    let windowTitle = Self.frontmostWindowName()
    OverlayWindow.beginAreaSelection { rect in
        guard let rect = rect else { return }
        let modifiers = NSEvent.modifierFlags  // capture at mouse-up moment
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
```

Apply the same pattern to `startFullscreenCapture`, `startWindowCapture`, and `startFreezeCapture`. For fullscreen (no mouse-up), read modifiers at call time.

**Step 3: Build and test**

Run: `make run`
Test each modifier:
- Cmd+Shift+4 then drag (no mods) → QAO appears as before
- Cmd+Shift+4 then drag while holding Option → saves to desktop, toast shows
- Cmd+Shift+4 then drag while holding Control → copied to clipboard, toast shows
- Cmd+Shift+4 then drag while holding Shift → editor opens directly

**Step 4: Commit**

```bash
git add Znap/Sources/AppDelegate.swift
git commit -m "feat: add destination modifiers — Option=save, Ctrl=copy, Shift=edit"
```

---

### Task 4: Hide Desktop Icons in Capture Flow (Feature 2)

Wire DesktopIconManager into the capture flow based on preferences.

**Files:**
- Modify: `Znap/Sources/AppDelegate.swift` (wrap capture methods)
- Modify: `Znap/Sources/ZnapApp.swift:36-42` (already has toggle — verify)

**Step 1: Add hide/restore wrapper to AppDelegate**

```swift
/// Wraps a capture operation with desktop icon hide/restore if enabled.
/// The restore happens after a short delay to ensure the capture completes
/// after Finder restarts.
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
```

**Step 2: Wrap each capture method**

For area capture:
```swift
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
```

Apply same pattern to `startFullscreenCapture`, `startWindowCapture`, `startFreezeCapture`.

**Step 3: Verify menu bar toggle already works**

The menu bar already has a "Hide Desktop Icons" / "Show Desktop Icons" toggle in `ZnapApp.swift:36-42`. Verify it still works correctly.

**Step 4: Build and test**

Run: `make run`
Test: Enable "Auto-Hide Desktop Icons" in Preferences → capture → icons should hide, capture, then restore.

**Step 5: Commit**

```bash
git add Znap/Sources/AppDelegate.swift
git commit -m "feat: auto-hide desktop icons during capture when enabled"
```

---

### Task 5: Window Shadow Toggle in UI (Feature 6)

Expose existing preference in PreferencesView and add menu bar toggle.

**Files:**
- Modify: `Znap/Sources/ZnapApp.swift` (add shadow toggle to menu)

**Step 1: Verify PreferencesView already has the toggle**

Check `PreferencesView.swift:72` — it already has:
```swift
Toggle("Include Window Shadow", isOn: $prefs.includeWindowShadow)
```

This is done. No changes needed to PreferencesView.

**Step 2: Add quick toggle to menu bar**

In `ZnapApp.swift`, add a shadow toggle near the desktop icons toggle:

```swift
// After the Desktop Icons toggle, add:
Button(UserDefaults.standard.bool(forKey: "includeWindowShadow")
    ? "✓ Window Shadow"
    : "  Window Shadow") {
    let current = UserDefaults.standard.bool(forKey: "includeWindowShadow")
    UserDefaults.standard.set(!current, forKey: "includeWindowShadow")
}
```

Note: Since `ZnapPreferences` uses `@AppStorage`, flipping the UserDefault directly works and the PreferencesView will stay in sync.

**Step 3: Build and test**

Run: `make run`
Test: Click menu bar → toggle "Window Shadow" → capture a window → verify shadow is included or removed.

**Step 4: Commit**

```bash
git add Znap/Sources/ZnapApp.swift
git commit -m "feat: add window shadow quick toggle to menu bar"
```

---

### Task 6: GIF Export from Recordings (Feature 3)

Add "Export as GIF" button to VideoEditorPanel.

**Files:**
- Modify: `Znap/Sources/UI/VideoEditorPanel.swift`
- Modify: `Znap/Sources/Models/Preferences.swift`
- Modify: `Znap/Sources/UI/PreferencesView.swift`

**Step 1: Add GIF frame rate preference**

In `Preferences.swift`, add:

```swift
// MARK: - GIF

/// Frames per second for GIF exports.
@AppStorage("gifFrameRate") var gifFrameRate = 10
```

In `PreferencesView.swift`, add to the recording tab:

```swift
Stepper("GIF Frame Rate: \(prefs.gifFrameRate) fps", value: $prefs.gifFrameRate, in: 5...15, step: 5)
```

**Step 2: Add Export GIF button to VideoEditorPanel**

Add a new button next to the save button:

```swift
private let gifButton = NSButton(title: "Export GIF", target: nil, action: nil)
```

In `setupUI()`, configure the GIF button:

```swift
gifButton.translatesAutoresizingMaskIntoConstraints = false
gifButton.target = self
gifButton.action = #selector(exportGIFAction)
gifButton.bezelStyle = .rounded
bottomBar.addSubview(gifButton)
```

Add layout constraints placing gifButton to the left of cancelButton:

```swift
gifButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
gifButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
```

**Step 3: Implement exportGIFAction**

```swift
@objc private func exportGIFAction() {
    guard let videoURL else { return }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.gif]
    panel.nameFieldStringValue = "recording.gif"
    panel.canCreateDirectories = true

    panel.beginSheetModal(for: self) { [weak self] response in
        guard let self, response == .OK, let outputURL = panel.url else { return }

        self.gifButton.isEnabled = false
        self.saveButton.isEnabled = false
        self.cancelButton.isEnabled = false

        Task { [weak self] in
            guard let self else { return }
            do {
                let segments = self.timelineView.segments
                let composition = try await VideoExportService.buildComposition(
                    source: videoURL, segments: segments
                )
                let fps = ZnapPreferences().gifFrameRate
                let frames = try await self.extractFrames(
                    from: composition, fps: fps
                )
                let frameDelay = 1.0 / Double(fps)
                let success = GIFEncoder.encode(
                    frames: frames, frameDelay: frameDelay, outputURL: outputURL
                )

                await MainActor.run {
                    self.gifButton.isEnabled = true
                    self.saveButton.isEnabled = true
                    self.cancelButton.isEnabled = true

                    if success {
                        ToastPanel.show("GIF saved", icon: "checkmark.circle")
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "GIF export failed"
                        alert.runModal()
                    }
                }
            } catch {
                await MainActor.run {
                    self.gifButton.isEnabled = true
                    self.saveButton.isEnabled = true
                    self.cancelButton.isEnabled = true
                    let alert = NSAlert(error: error)
                    alert.beginSheetModal(for: self)
                }
            }
        }
    }
}

/// Extracts CGImage frames from a composition at the given frame rate.
private func extractFrames(from composition: AVMutableComposition, fps: Int) async throws -> [CGImage] {
    let generator = AVAssetImageGenerator(asset: composition)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    // Scale down for GIF size — max 640px wide
    generator.maximumSize = CGSize(width: 640, height: 0)

    let duration = try await composition.load(.duration)
    let totalSeconds = CMTimeGetSeconds(duration)
    let frameCount = Int(totalSeconds * Double(fps))
    guard frameCount > 0 else { return [] }

    var frames: [CGImage] = []
    for i in 0..<frameCount {
        let time = CMTime(seconds: Double(i) / Double(fps), preferredTimescale: 600)
        let (cgImage, _) = try await generator.image(at: time)
        frames.append(cgImage)
    }
    return frames
}
```

**Step 4: Expose buildComposition in VideoExportService**

`VideoExportService.export` currently builds the composition internally. Extract the composition building into a public static method so the GIF exporter can reuse it:

In `VideoExportService.swift`, refactor to expose:

```swift
/// Builds an AVMutableComposition from the source video applying segment edits.
static func buildComposition(source: URL, segments: [Segment]) async throws -> AVMutableComposition {
    // ... (extract the composition-building logic from export())
}
```

Then `export()` calls `buildComposition()` internally.

**Step 5: Build and test**

Run: `make run`
Test: Record a short video → open editor → click "Export GIF" → save → verify .gif file plays correctly.

**Step 6: Commit**

```bash
git add Znap/Sources/UI/VideoEditorPanel.swift Znap/Sources/Services/VideoExportService.swift Znap/Sources/Models/Preferences.swift Znap/Sources/UI/PreferencesView.swift
git commit -m "feat: add GIF export from video editor with configurable frame rate"
```

---

### Task 7: Per-Mode Hotkey Customization (Feature 1)

Custom keyboard shortcut recorder and preferences tab.

**Files:**
- Create: `Znap/Sources/UI/ShortcutRecorderView.swift`
- Modify: `Znap/Sources/Models/Preferences.swift`
- Modify: `Znap/Sources/UI/PreferencesView.swift`
- Modify: `Znap/Sources/AppDelegate.swift:24-81`
- Modify: `Znap/Sources/ZnapApp.swift` (update menu shortcut labels)

**Step 1: Define hotkey mode identifiers and defaults**

In `Preferences.swift`, add a struct and defaults:

```swift
/// Represents a persisted keyboard shortcut binding.
struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon modifier flags

    /// Human-readable string like "⌘⇧4"
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(Carbon.controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(Carbon.optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(Carbon.shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(Carbon.cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }
}

/// All capture modes with their default shortcuts.
enum CaptureMode: String, CaseIterable {
    case allInOne = "allInOne"
    case area = "area"
    case fullscreen = "fullscreen"
    case window = "window"
    case freeze = "freeze"
    case ocr = "ocr"
    case scroll = "scroll"
    case record = "record"

    var label: String {
        switch self {
        case .allInOne: return "All-In-One"
        case .area: return "Capture Area"
        case .fullscreen: return "Capture Fullscreen"
        case .window: return "Capture Window"
        case .freeze: return "Freeze & Capture"
        case .ocr: return "OCR Text"
        case .scroll: return "Scrolling Capture"
        case .record: return "Record Screen"
        }
    }

    var defaultBinding: HotkeyBinding {
        switch self {
        case .allInOne:  return HotkeyBinding(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .area:      return HotkeyBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .fullscreen:return HotkeyBinding(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .window:    return HotkeyBinding(keyCode: UInt32(kVK_ANSI_8), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .freeze:    return HotkeyBinding(keyCode: UInt32(kVK_ANSI_6), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .ocr:       return HotkeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .scroll:    return HotkeyBinding(keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .record:    return HotkeyBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        }
    }
}
```

Add persistence helpers to `ZnapPreferences`:

```swift
/// Returns the saved binding for a mode, or the default.
func binding(for mode: CaptureMode) -> HotkeyBinding {
    let key = "hotkey_\(mode.rawValue)"
    guard let data = UserDefaults.standard.data(forKey: key),
          let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    else { return mode.defaultBinding }
    return binding
}

/// Saves a binding for a mode.
func setBinding(_ binding: HotkeyBinding, for mode: CaptureMode) {
    let key = "hotkey_\(mode.rawValue)"
    if let data = try? JSONEncoder().encode(binding) {
        UserDefaults.standard.set(data, forKey: key)
    }
}
```

**Step 2: Create ShortcutRecorderView**

```swift
// ShortcutRecorderView.swift
import SwiftUI
import Carbon

/// A view that captures a keyboard shortcut when clicked.
struct ShortcutRecorderView: View {
    let mode: CaptureMode
    @Binding var binding: HotkeyBinding
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(mode.label)
            Spacer()
            Button(isRecording ? "Press shortcut..." : binding.displayString) {
                isRecording = true
            }
            .frame(width: 120)
            .background(
                ShortcutRecorderNSView(isRecording: $isRecording, binding: $binding)
                    .frame(width: 0, height: 0)
            )
        }
    }
}

/// NSView-based key event monitor for capturing shortcuts.
struct ShortcutRecorderNSView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var binding: HotkeyBinding

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isRecording = isRecording
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording, binding: $binding)
    }

    class Coordinator {
        var isRecording = false {
            didSet {
                if isRecording { startMonitoring() }
                else { stopMonitoring() }
            }
        }
        var isRecordingBinding: Binding<Bool>
        var bindingBinding: Binding<HotkeyBinding>
        var monitor: Any?

        init(isRecording: Binding<Bool>, binding: Binding<HotkeyBinding>) {
            self.isRecordingBinding = isRecording
            self.bindingBinding = binding
        }

        func startMonitoring() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isRecording else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                // Escape cancels recording
                if event.keyCode == 53 {
                    self.isRecordingBinding.wrappedValue = false
                    return nil
                }

                // Require at least Cmd or Ctrl modifier
                guard flags.contains(.command) || flags.contains(.control) else { return event }

                // Convert Cocoa modifier flags to Carbon
                var carbonMods: UInt32 = 0
                if flags.contains(.command) { carbonMods |= UInt32(Carbon.cmdKey) }
                if flags.contains(.shift) { carbonMods |= UInt32(Carbon.shiftKey) }
                if flags.contains(.option) { carbonMods |= UInt32(Carbon.optionKey) }
                if flags.contains(.control) { carbonMods |= UInt32(Carbon.controlKey) }

                self.bindingBinding.wrappedValue = HotkeyBinding(
                    keyCode: UInt32(event.keyCode),
                    modifiers: carbonMods
                )
                self.isRecordingBinding.wrappedValue = false
                return nil
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stopMonitoring() }
    }
}
```

**Step 3: Add Shortcuts tab to PreferencesView**

```swift
// Add to PreferencesView body TabView:
shortcutsTab
    .tabItem { Label("Shortcuts", systemImage: "keyboard") }

// Increase frame height:
.frame(width: 420, height: 340)

// Add the tab:
private var shortcutsTab: some View {
    Form {
        ForEach(CaptureMode.allCases, id: \.self) { mode in
            ShortcutRecorderRow(mode: mode)
        }
    }
    .padding()
}
```

Create a `ShortcutRecorderRow` that reads/writes from `ZnapPreferences`.

**Step 4: Refactor AppDelegate.registerHotkeys()**

Replace hardcoded registrations with a loop over `CaptureMode.allCases`:

```swift
private var registeredHotkeyIDs: [UInt32] = []

private func registerHotkeys() {
    let prefs = ZnapPreferences()
    let handlers: [CaptureMode: () -> Void] = [
        .allInOne: { [weak self] in self?.showAllInOne() },
        .area: { [weak self] in self?.startAreaCapture() },
        .fullscreen: { [weak self] in self?.startFullscreenCapture() },
        .window: { [weak self] in self?.startWindowCapture() },
        .freeze: { [weak self] in self?.startFreezeCapture() },
        .ocr: { [weak self] in self?.startOCRCapture() },
        .scroll: { [weak self] in self?.startScrollCapture() },
        .record: { [weak self] in self?.toggleRecording() },
    ]
    for mode in CaptureMode.allCases {
        let binding = prefs.binding(for: mode)
        guard let handler = handlers[mode] else { continue }
        let id = HotkeyService.shared.register(
            keyCode: binding.keyCode,
            modifiers: binding.modifiers,
            handler: handler
        )
        registeredHotkeyIDs.append(id)
    }
}
```

Add an `unregister(id:)` method to `HotkeyService` and a `reregisterHotkeys()` method to `AppDelegate` that unregisters all and re-registers. Call this when preferences change.

**Step 5: Update menu bar shortcut labels**

In `ZnapApp.swift`, read the display string from preferences instead of hardcoded strings:

```swift
let prefs = ZnapPreferences()
Button("Capture Area (\(prefs.binding(for: .area).displayString))") { ... }
```

**Step 6: Add keyCodeToString helper**

A helper function that converts Carbon key codes to human-readable strings (e.g., `kVK_ANSI_4` → "4", `kVK_ANSI_R` → "R").

**Step 7: Build and test**

Run: `make run`
Test: Open Preferences → Shortcuts tab → click a field → press new combo → verify it takes effect.

**Step 8: Commit**

```bash
git add Znap/Sources/UI/ShortcutRecorderView.swift Znap/Sources/Models/Preferences.swift Znap/Sources/UI/PreferencesView.swift Znap/Sources/AppDelegate.swift Znap/Sources/Services/HotkeyService.swift Znap/Sources/ZnapApp.swift
git commit -m "feat: add customizable per-mode keyboard shortcuts with recorder UI"
```

---

### Task 8: Update Specs and Docs

**Files:**
- Modify: `docs/specs/PRODUCT.md`
- Modify: `docs/specs/ROADMAP.md`
- Modify: `docs/app-store/LISTING.md`
- Modify: `docs/app-store/ASO.md`

**Step 1: Update all spec files**

- PRODUCT.md: Add ToastPanel to UI layer, ShortcutRecorderView to UI, destination modifiers to post-capture flow, GIF export to recording features, hotkey customization to preferences.
- ROADMAP.md: Mark all 6 Tier 1 features as "Done", add v0.2 to version history.
- LISTING.md: Update description with new features, update "What's New", add "GIF" to keywords.
- ASO.md: Add "GIF", "customizable shortcuts" to keyword strategy.

**Step 2: Commit**

```bash
git add docs/
git commit -m "docs: update specs for v0.2 — all tier 1 features complete"
```

---

## Task Execution Order

```
Task 1: ToastView (shared infra, no dependencies)
Task 2: OCR Toast (depends on Task 1)
Task 3: Destination Modifiers (depends on Task 1)
Task 4: Hide Desktop Icons (depends on Task 3 for modifier-aware capture flow)
Task 5: Window Shadow Toggle (independent, easy)
Task 6: GIF Export (independent, medium)
Task 7: Hotkey Customization (independent, largest task)
Task 8: Update Specs (depends on all above)
```

Tasks 5, 6, and 7 are independent and could be parallelized.
