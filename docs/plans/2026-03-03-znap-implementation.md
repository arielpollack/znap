# Znap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menu bar screenshot app (CleanShot X alternative) with 10 core features, installable via CLI.

**Architecture:** Pure Swift, AppKit for system windows (overlays, floating panels), SwiftUI for content views (annotation editor, preferences, menu bar). No third-party runtime dependencies. xcodegen for project generation.

**Tech Stack:** Swift 5.9+, macOS 13+, AppKit, SwiftUI, ScreenCaptureKit, AVFoundation, Vision, Core Image, ImageIO, SwiftData

---

## Phase 1: Project Scaffolding & Menu Bar Shell

### Task 1: Initialize project structure

**Files:**
- Create: `project.yml`
- Create: `Znap/Sources/ZnapApp.swift`
- Create: `Znap/Sources/Info.plist`
- Create: `Znap/Sources/Znap.entitlements`
- Create: `Znap/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Makefile`
- Create: `.gitignore`

**Step 1: Create .gitignore**

```gitignore
# Xcode
*.xcodeproj
*.xcworkspace
build/
DerivedData/
*.xcuserdata
# macOS
.DS_Store
# Build
*.app
*.dmg
```

**Step 2: Create project.yml for xcodegen**

```yaml
name: Znap
options:
  bundleIdPrefix: com.znap
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"
  minimumXcodeGenVersion: "2.35"
settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "13.0"
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_ENTITLEMENTS: Znap/Sources/Znap.entitlements
targets:
  Znap:
    type: application
    platform: macOS
    sources:
      - path: Znap/Sources
    resources:
      - path: Znap/Resources
    info:
      path: Znap/Sources/Info.plist
    entitlements:
      path: Znap/Sources/Znap.entitlements
    settings:
      base:
        INFOPLIST_FILE: Znap/Sources/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.znap.app
        PRODUCT_NAME: Znap
        LD_RUNPATH_SEARCH_PATHS: "@executable_path/../Frameworks"
  ZnapTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Znap/Tests
    dependencies:
      - target: Znap
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.znap.tests
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Znap.app/Contents/MacOS/Znap"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

**Step 3: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Znap</string>
    <key>CFBundleDisplayName</key>
    <string>Znap</string>
    <key>CFBundleIdentifier</key>
    <string>com.znap.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Znap</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Znap needs screen recording permission to capture screenshots and record your screen.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Znap needs microphone access to record audio during screen recordings.</string>
</dict>
</plist>
```

Note: `LSUIElement = true` hides the app from the Dock — menu bar only.

**Step 4: Create entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

Non-sandboxed for global hotkeys and CGEvent taps.

**Step 5: Create minimal ZnapApp.swift**

```swift
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
```

**Step 6: Create empty Assets.xcassets**

```json
{
  "images": [],
  "info": { "version": 1, "author": "xcode" }
}
```

**Step 7: Create Makefile**

```makefile
.PHONY: generate build run install clean dmg

PROJECT = Znap.xcodeproj
SCHEME = Znap
BUILD_DIR = build
APP_NAME = Znap.app

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(BUILD_DIR) build

run: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD_DIR) build
	open $(BUILD_DIR)/Build/Products/Debug/$(APP_NAME)

install: build
	cp -R $(BUILD_DIR)/Build/Products/Release/$(APP_NAME) /Applications/

test: generate
	xcodebuild -project $(PROJECT) -scheme ZnapTests -configuration Debug \
		-derivedDataPath $(BUILD_DIR) test

clean:
	rm -rf $(BUILD_DIR) $(PROJECT)

dmg: build
	./scripts/create-dmg.sh
```

**Step 8: Create tests directory with placeholder**

Create: `Znap/Tests/ZnapTests.swift`

```swift
import XCTest

final class ZnapTests: XCTestCase {
    func testAppLaunches() {
        XCTAssertTrue(true)
    }
}
```

**Step 9: Generate project and verify build**

Run: `brew list xcodegen || brew install xcodegen`
Run: `make build`
Expected: BUILD SUCCEEDED

**Step 10: Verify app runs**

Run: `make run`
Expected: Menu bar icon appears with "Znap v0.1.0" and Quit button.

**Step 11: Commit**

```bash
git add -A && git commit -m "feat: project scaffolding with menu bar shell"
```

---

## Phase 2: Global Hotkeys + Area Capture + Quick Access Overlay

This phase delivers the first working screenshot flow: press hotkey → select area → see QAO.

### Task 2: HotkeyService — global keyboard shortcuts

**Files:**
- Create: `Znap/Sources/Services/HotkeyService.swift`
- Create: `Znap/Tests/HotkeyServiceTests.swift`

**Step 1: Write HotkeyService**

Uses Carbon `RegisterEventHotKey` API for global hotkeys. This is the only reliable way to register system-wide hotkeys on macOS without Accessibility permission for basic hotkeys.

```swift
import Carbon
import Cocoa

final class HotkeyService {
    static let shared = HotkeyService()

    struct Hotkey {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let handler: () -> Void
    }

    private var hotkeys: [UInt32: Hotkey] = [:]
    private var nextId: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?

    private init() {
        installHandler()
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32 {
        let id = nextId
        nextId += 1

        let hotkey = Hotkey(id: id, keyCode: keyCode, modifiers: modifiers, handler: handler)
        hotkeys[id] = hotkey

        var hotkeyID = EventHotKeyID(signature: OSType(0x5A4E4150), id: id) // "ZNAP"
        var hotkeyRef: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef)

        return id
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()

            var hotkeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                            nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)

            if let hotkey = service.hotkeys[hotkeyID.id] {
                DispatchQueue.main.async { hotkey.handler() }
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandlerRef)
    }
}

// Carbon modifier helpers
extension HotkeyService {
    static let cmdKey = UInt32(cmdKey)
    static let shiftKey = UInt32(shiftKey)
    static let optionKey = UInt32(optionKey)
    static let controlKey = UInt32(controlKey)
}
```

**Step 2: Write basic test**

```swift
import XCTest
@testable import Znap

final class HotkeyServiceTests: XCTestCase {
    func testServiceIsSingleton() {
        let a = HotkeyService.shared
        let b = HotkeyService.shared
        XCTAssertTrue(a === b)
    }

    func testRegisterReturnsIncrementingIds() {
        let id1 = HotkeyService.shared.register(keyCode: 0, modifiers: 0) {}
        let id2 = HotkeyService.shared.register(keyCode: 1, modifiers: 0) {}
        XCTAssertEqual(id2, id1 + 1)
    }
}
```

**Step 3: Run tests**

Run: `make test`
Expected: PASS

**Step 4: Commit**

```bash
git add Znap/Sources/Services/HotkeyService.swift Znap/Tests/HotkeyServiceTests.swift
git commit -m "feat: add HotkeyService for global keyboard shortcuts"
```

### Task 3: CaptureService — ScreenCaptureKit wrapper

**Files:**
- Create: `Znap/Sources/Services/CaptureService.swift`

**Step 1: Write CaptureService**

```swift
import ScreenCaptureKit
import CoreGraphics
import AppKit

final class CaptureService {
    static let shared = CaptureService()

    enum CaptureMode {
        case area(CGRect)
        case window(CGWindowID)
        case fullscreen(CGDirectDisplayID)
    }

    func captureArea(_ rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { display in
            NSRect(x: CGFloat(display.frame.origin.x), y: CGFloat(display.frame.origin.y),
                   width: CGFloat(display.frame.width), height: CGFloat(display.frame.height)).contains(rect.origin)
        }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        // Scale rect to pixel coordinates for Retina
        let scaleFactor = CGFloat(display.width) / display.frame.width
        config.sourceRect = CGRect(
            x: (rect.origin.x - display.frame.origin.x) * scaleFactor,
            y: (rect.origin.y - display.frame.origin.y) * scaleFactor,
            width: rect.width * scaleFactor,
            height: rect.height * scaleFactor
        )
        config.width = Int(rect.width * scaleFactor)
        config.height = Int(rect.height * scaleFactor)
        config.showsCursor = false
        config.capturesAudio = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return image
    }

    func captureWindow(_ windowID: CGWindowID) async throws -> CGImage {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution]) else {
            throw CaptureError.captureFailed
        }
        return image
    }

    func captureFullscreen(_ displayID: CGDirectDisplayID? = nil) async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let display = displayID.flatMap({ id in content.displays.first { $0.displayID == id } }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    enum CaptureError: Error {
        case noDisplay
        case captureFailed
        case permissionDenied
    }
}
```

**Step 2: Commit**

```bash
git add Znap/Sources/Services/CaptureService.swift
git commit -m "feat: add CaptureService wrapping ScreenCaptureKit"
```

### Task 4: OverlayWindow — capture area selection UI

**Files:**
- Create: `Znap/Sources/UI/OverlayWindow.swift`
- Create: `Znap/Sources/UI/SelectionView.swift`

**Step 1: Write OverlayWindow**

```swift
import AppKit

final class OverlayWindow: NSPanel {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init(for screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.001) // near-transparent to receive events
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true

        let selectionView = SelectionView(frame: screen.frame)
        selectionView.onSelection = { [weak self] rect in
            self?.onSelection?(rect)
            self?.close()
        }
        selectionView.onCancel = { [weak self] in
            self?.onCancel?()
            self?.close()
        }
        self.contentView = selectionView
    }

    static func beginAreaSelection(completion: @escaping (CGRect?) -> Void) {
        var windows: [OverlayWindow] = []

        for screen in NSScreen.screens {
            let window = OverlayWindow(for: screen)
            window.onSelection = { rect in
                windows.forEach { $0.close() }
                windows.removeAll()
                completion(rect)
            }
            window.onCancel = {
                windows.forEach { $0.close() }
                windows.removeAll()
                completion(nil)
            }
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        NSCursor.crosshair.push()
    }
}
```

**Step 2: Write SelectionView**

```swift
import AppKit

final class SelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var isSelecting = false
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isSelecting = true
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        currentPoint = convert(event.locationInWindow, from: nil)

        // Hold Shift to lock aspect ratio (1:1)
        if event.modifierFlags.contains(.shift), let start = startPoint, let current = currentPoint {
            let dx = current.x - start.x
            let dy = current.y - start.y
            let size = max(abs(dx), abs(dy))
            currentPoint = NSPoint(x: start.x + size * (dx >= 0 ? 1 : -1),
                                   y: start.y + size * (dy >= 0 ? 1 : -1))
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isSelecting, let rect = selectionRect, rect.width > 5, rect.height > 5 else {
            isSelecting = false
            needsDisplay = true
            return
        }

        isSelecting = false
        // Convert from view coords to screen coords
        let screenRect = window?.convertToScreen(rect) ?? rect
        onSelection?(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel?()
        }
    }

    private var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(x: min(start.x, current.x),
                      y: min(start.y, current.y),
                      width: abs(current.x - start.x),
                      height: abs(current.y - start.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()

        guard let rect = selectionRect, isSelecting else { return }

        // Clear selection area
        NSColor.clear.setFill()
        rect.fill(using: .copy)

        // Selection border
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.stroke()

        // Dimension label
        let w = Int(rect.width)
        let h = Int(rect.height)
        let label = "\(w) × \(h)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        let labelSize = label.size(withAttributes: attrs)
        let labelPoint = NSPoint(x: rect.midX - labelSize.width / 2,
                                  y: rect.minY - labelSize.height - 6)
        label.draw(at: labelPoint, withAttributes: attrs)
    }
}
```

**Step 3: Verify build**

Run: `make build`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add Znap/Sources/UI/OverlayWindow.swift Znap/Sources/UI/SelectionView.swift
git commit -m "feat: add overlay window for area selection with crosshair"
```

### Task 5: QuickAccessOverlay — post-capture floating thumbnail

**Files:**
- Create: `Znap/Sources/UI/QuickAccessOverlay.swift`
- Create: `Znap/Sources/UI/QuickAccessView.swift`

**Step 1: Write QuickAccessOverlay (NSPanel)**

```swift
import AppKit

final class QuickAccessOverlay: NSPanel {
    private let capturedImage: NSImage
    private var dismissTimer: Timer?
    private static var current: QuickAccessOverlay?

    init(image: NSImage) {
        self.capturedImage = image

        let width: CGFloat = 280
        let height: CGFloat = 80

        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            return
        }

        let origin = NSPoint(
            x: screen.visibleFrame.maxX - width - 16,
            y: screen.visibleFrame.minY + 16
        )

        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.isMovableByWindowBackground = true
        self.animationBehavior = .utilityWindow

        let view = QuickAccessView(image: image, frame: NSRect(origin: .zero, size: NSSize(width: width, height: height)))
        view.onAction = { [weak self] action in self?.handleAction(action) }
        self.contentView = view
    }

    static func show(image: NSImage) {
        current?.close()
        let overlay = QuickAccessOverlay(image: image)
        overlay.makeKeyAndOrderFront(nil)
        overlay.startDismissTimer()
        current = overlay
    }

    static func restoreLast() {
        current?.makeKeyAndOrderFront(nil)
    }

    private func startDismissTimer() {
        // TODO: Read from preferences, default 15s
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.animateOut()
        }
    }

    private func animateOut() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        })
    }

    enum Action {
        case openAnnotate
        case copyToClipboard
        case save
        case saveAs
        case pin
        case dismiss
    }

    private func handleAction(_ action: Action) {
        dismissTimer?.invalidate()
        switch action {
        case .copyToClipboard:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([capturedImage])
            animateOut()
        case .save:
            saveToDisk(capturedImage)
            animateOut()
        case .dismiss:
            animateOut()
        case .openAnnotate:
            // TODO: Phase 4
            break
        case .saveAs:
            // TODO: NSSavePanel
            break
        case .pin:
            // TODO: Phase 10
            break
        }
    }

    private func saveToDisk(_ image: NSImage) {
        // TODO: Read default path from preferences
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let filename = "Znap-\(formatter.string(from: Date())).png"
        let url = desktop.appendingPathComponent(filename)

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }

        try? png.write(to: url)
    }
}
```

**Step 2: Write QuickAccessView**

```swift
import AppKit

final class QuickAccessView: NSView {
    var onAction: ((QuickAccessOverlay.Action) -> Void)?

    private let imageView: NSImageView
    private let infoLabel: NSTextField
    private let image: NSImage

    init(image: NSImage, frame: NSRect) {
        self.image = image
        self.imageView = NSImageView()
        self.infoLabel = NSTextField(labelWithString: "")
        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5

        // Thumbnail
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(x: 8, y: 8, width: 64, height: 64)
        addSubview(imageView)

        // Info
        let w = Int(image.size.width)
        let h = Int(image.size.height)
        infoLabel.stringValue = "\(w) × \(h)"
        infoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.frame = NSRect(x: 80, y: 40, width: 180, height: 20)
        addSubview(infoLabel)

        // Hint
        let hint = NSTextField(labelWithString: "⌘C copy  ⌘S save  Click annotate")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 80, y: 12, width: 190, height: 16)
        addSubview(hint)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        switch (cmd, event.keyCode) {
        case (true, 8):  onAction?(.copyToClipboard) // Cmd+C
        case (true, 1):  onAction?(.save)            // Cmd+S
        case (true, 13): onAction?(.dismiss)         // Cmd+W
        case (_, 53):    onAction?(.dismiss)         // ESC
        default: super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onAction?(.openAnnotate)
    }

    override var acceptsFirstResponder: Bool { true }

    // Drag support
    override func mouseDragged(with event: NSEvent) {
        let dragItem = NSDraggingItem(pasteboardWriter: image)
        dragItem.setDraggingFrame(imageView.frame, contents: image)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }
}

extension QuickAccessView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
}
```

**Step 3: Commit**

```bash
git add Znap/Sources/UI/QuickAccessOverlay.swift Znap/Sources/UI/QuickAccessView.swift
git commit -m "feat: add Quick Access Overlay for post-capture workflow"
```

### Task 6: Wire up the capture flow in ZnapApp

**Files:**
- Modify: `Znap/Sources/ZnapApp.swift`
- Create: `Znap/Sources/AppDelegate.swift`

**Step 1: Create AppDelegate to manage hotkeys and capture flow**

```swift
import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        registerHotkeys()
    }

    private func registerHotkeys() {
        // Cmd+Shift+4 for area capture (matching macOS convention)
        HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_4),
            modifiers: UInt32(cmdKey | shiftKey),
            handler: { [weak self] in self?.startAreaCapture() }
        )

        // Cmd+Shift+3 for fullscreen
        HotkeyService.shared.register(
            keyCode: UInt32(kVK_ANSI_3),
            modifiers: UInt32(cmdKey | shiftKey),
            handler: { [weak self] in self?.startFullscreenCapture() }
        )
    }

    private func startAreaCapture() {
        OverlayWindow.beginAreaSelection { rect in
            guard let rect = rect else { return }
            NSCursor.pop()
            Task {
                do {
                    let cgImage = try await CaptureService.shared.captureArea(rect)
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    await MainActor.run {
                        QuickAccessOverlay.show(image: nsImage)
                    }
                } catch {
                    print("Capture failed: \(error)")
                }
            }
        }
    }

    private func startFullscreenCapture() {
        Task {
            do {
                let cgImage = try await CaptureService.shared.captureFullscreen()
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                await MainActor.run {
                    QuickAccessOverlay.show(image: nsImage)
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }
}
```

**Step 2: Update ZnapApp.swift to use AppDelegate**

```swift
import SwiftUI

@main
struct ZnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Znap", systemImage: "camera.viewfinder") {
            Button("Capture Area (⌘⇧4)") { appDelegate.startAreaCapture() }
            Button("Capture Fullscreen (⌘⇧3)") { appDelegate.startFullscreenCapture() }
            Divider()
            Text("Znap v0.1.0").foregroundColor(.secondary)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
```

Note: Make `startAreaCapture` and `startFullscreenCapture` internal (remove `private`) so the menu bar can call them too.

**Step 3: Build and manually test**

Run: `make run`
Expected: App launches in menu bar. Press Cmd+Shift+4 → crosshair overlay appears → drag to select → QAO shows with thumbnail. Cmd+C copies image. Cmd+S saves PNG to Desktop.

**Step 4: Commit**

```bash
git add Znap/Sources/ZnapApp.swift Znap/Sources/AppDelegate.swift
git commit -m "feat: wire area + fullscreen capture flow end-to-end"
```

---

## Phase 3: Window Capture + Freeze Screen

### Task 7: Window capture mode

**Files:**
- Create: `Znap/Sources/UI/WindowHighlightOverlay.swift`
- Modify: `Znap/Sources/AppDelegate.swift`

**Step 1: Write WindowHighlightOverlay**

An overlay that highlights the window under the cursor and captures it on click.

```swift
import AppKit

final class WindowHighlightOverlay: NSPanel {
    var onCapture: ((CGWindowID) -> Void)?
    var onCancel: (() -> Void)?
    private var highlightWindow: NSWindow?
    private var currentWindowID: CGWindowID?

    init() {
        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            return
        }
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let trackingView = WindowTrackingView(frame: screen.frame)
        trackingView.onWindowHover = { [weak self] windowID, frame in
            self?.highlightFrame(frame)
            self?.currentWindowID = windowID
        }
        trackingView.onClick = { [weak self] in
            guard let id = self?.currentWindowID else { return }
            self?.highlightWindow?.close()
            self?.close()
            self?.onCapture?(id)
        }
        trackingView.onCancel = { [weak self] in
            self?.highlightWindow?.close()
            self?.close()
            self?.onCancel?()
        }
        contentView = trackingView
    }

    private func highlightFrame(_ frame: CGRect) {
        highlightWindow?.close()
        let hw = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        hw.level = .screenSaver
        hw.isOpaque = false
        hw.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15)
        hw.hasShadow = false
        hw.ignoresMouseEvents = true
        hw.orderFront(nil)
        highlightWindow = hw
    }

    static func beginWindowSelection(completion: @escaping (CGWindowID?) -> Void) {
        let overlay = WindowHighlightOverlay()
        overlay.onCapture = { windowID in
            completion(windowID)
        }
        overlay.onCancel = {
            completion(nil)
        }
        overlay.makeKeyAndOrderFront(nil)
    }
}

private final class WindowTrackingView: NSView {
    var onWindowHover: ((CGWindowID, CGRect) -> Void)?
    var onClick: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseMoved(with event: NSEvent) {
        let mouseLocation = NSEvent.mouseLocation
        // Get window list, find window under cursor (excluding our own windows)
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }

        for info in windowList {
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != ProcessInfo.processInfo.processIdentifier else { continue }

            let bounds = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                               width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)

            // Convert from CG coords (top-left origin) to NS coords (bottom-left origin)
            guard let screenHeight = NSScreen.main?.frame.height else { continue }
            let nsRect = NSRect(x: bounds.origin.x,
                               y: screenHeight - bounds.origin.y - bounds.height,
                               width: bounds.width, height: bounds.height)

            if nsRect.contains(mouseLocation) {
                onWindowHover?(windowID, nsRect)
                return
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways], owner: self))
    }
}
```

**Step 2: Add window capture to AppDelegate**

Add to `AppDelegate`:
```swift
// Register hotkey: Cmd+Shift+5 for window capture
HotkeyService.shared.register(
    keyCode: UInt32(kVK_ANSI_5),
    modifiers: UInt32(cmdKey | shiftKey),
    handler: { [weak self] in self?.startWindowCapture() }
)

func startWindowCapture() {
    WindowHighlightOverlay.beginWindowSelection { windowID in
        guard let windowID = windowID else { return }
        Task {
            do {
                let cgImage = try await CaptureService.shared.captureWindow(windowID)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                await MainActor.run {
                    QuickAccessOverlay.show(image: nsImage)
                }
            } catch {
                print("Window capture failed: \(error)")
            }
        }
    }
}
```

**Step 3: Add menu bar button**

Add to `MenuBarExtra` body:
```swift
Button("Capture Window (⌘⇧5)") { appDelegate.startWindowCapture() }
```

**Step 4: Build and test**

Run: `make run`
Expected: Cmd+Shift+5 → hovering highlights windows with blue tint → click captures → QAO appears.

**Step 5: Commit**

```bash
git add Znap/Sources/UI/WindowHighlightOverlay.swift Znap/Sources/AppDelegate.swift Znap/Sources/ZnapApp.swift
git commit -m "feat: add window capture with highlight overlay"
```

### Task 8: Freeze screen mode

**Files:**
- Create: `Znap/Sources/UI/FreezeScreenOverlay.swift`
- Modify: `Znap/Sources/AppDelegate.swift`

**Step 1: Write FreezeScreenOverlay**

Captures all screens, displays them as frozen images, then allows area selection on top.

```swift
import AppKit

final class FreezeScreenOverlay {
    static func beginFrozenCapture(completion: @escaping (CGRect?) -> Void) {
        // Capture all screens first
        var frozenWindows: [NSWindow] = []

        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let cgImage = CGDisplayCreateImage(displayID) else { continue }

            let nsImage = NSImage(cgImage: cgImage, size: screen.frame.size)
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver - 1
            window.isOpaque = true
            window.backgroundColor = .black
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            imageView.image = nsImage
            imageView.imageScaling = .scaleAxesIndependently
            window.contentView = imageView
            window.orderFront(nil)
            frozenWindows.append(window)
        }

        // Now show the selection overlay on top of frozen screens
        OverlayWindow.beginAreaSelection { rect in
            frozenWindows.forEach { $0.close() }
            completion(rect)
        }
    }
}
```

**Step 2: Register hotkey in AppDelegate**

```swift
// Cmd+Shift+6 for freeze + capture
HotkeyService.shared.register(
    keyCode: UInt32(kVK_ANSI_6),
    modifiers: UInt32(cmdKey | shiftKey),
    handler: { [weak self] in self?.startFreezeCapture() }
)

func startFreezeCapture() {
    FreezeScreenOverlay.beginFrozenCapture { [weak self] rect in
        guard let rect = rect else { return }
        NSCursor.pop()
        Task {
            do {
                let cgImage = try await CaptureService.shared.captureArea(rect)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                await MainActor.run {
                    QuickAccessOverlay.show(image: nsImage)
                }
            } catch {
                print("Freeze capture failed: \(error)")
            }
        }
    }
}
```

**Step 3: Commit**

```bash
git add Znap/Sources/UI/FreezeScreenOverlay.swift Znap/Sources/AppDelegate.swift
git commit -m "feat: add freeze screen capture mode"
```

---

## Phase 4: Annotation Editor

### Task 9: Annotation data model

**Files:**
- Create: `Znap/Sources/Models/AnnotationDocument.swift`
- Create: `Znap/Tests/AnnotationDocumentTests.swift`

**Step 1: Write AnnotationDocument model**

```swift
import Foundation
import CoreGraphics

struct AnnotationDocument: Codable {
    var imageData: Data // PNG
    var annotations: [Annotation] = []
    var canvasSize: CGSize

    enum AnnotationType: String, Codable {
        case arrow, rectangle, filledRectangle, ellipse, line
        case text, counter, pixelate, blur, spotlight
        case highlighter, pencil
    }

    struct Annotation: Codable, Identifiable {
        let id: UUID
        var type: AnnotationType
        var startPoint: CGPoint
        var endPoint: CGPoint
        var points: [CGPoint]? // for pencil/highlighter
        var color: CodableColor
        var strokeWidth: CGFloat
        var text: String?
        var fontSize: CGFloat?
        var counterValue: Int?
        var isFilled: Bool
    }

    struct CodableColor: Codable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        static let defaultRed = CodableColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
        static let defaultYellow = CodableColor(red: 1, green: 0.84, blue: 0, alpha: 1)
    }
}
```

**Step 2: Write tests for Codable round-trip**

```swift
import XCTest
@testable import Znap

final class AnnotationDocumentTests: XCTestCase {
    func testCodableRoundTrip() throws {
        var doc = AnnotationDocument(imageData: Data([0x89, 0x50, 0x4E, 0x47]), canvasSize: CGSize(width: 800, height: 600))
        doc.annotations.append(AnnotationDocument.Annotation(
            id: UUID(), type: .arrow, startPoint: CGPoint(x: 10, y: 20), endPoint: CGPoint(x: 100, y: 200),
            points: nil, color: .defaultRed, strokeWidth: 2, text: nil, fontSize: nil, counterValue: nil, isFilled: false
        ))

        let encoded = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: encoded)

        XCTAssertEqual(decoded.annotations.count, 1)
        XCTAssertEqual(decoded.annotations[0].type, .arrow)
        XCTAssertEqual(decoded.canvasSize.width, 800)
    }
}
```

**Step 3: Run tests**

Run: `make test`
Expected: PASS

**Step 4: Commit**

```bash
git add Znap/Sources/Models/AnnotationDocument.swift Znap/Tests/AnnotationDocumentTests.swift
git commit -m "feat: add AnnotationDocument data model with Codable support"
```

### Task 10: Annotation editor window and canvas

**Files:**
- Create: `Znap/Sources/UI/AnnotationEditorWindow.swift`
- Create: `Znap/Sources/UI/AnnotationCanvasView.swift`
- Create: `Znap/Sources/UI/AnnotationToolbar.swift`

**Step 1: Write AnnotationEditorWindow (NSPanel host)**

```swift
import AppKit
import SwiftUI

final class AnnotationEditorWindow: NSPanel {
    private var document: AnnotationDocument

    init(image: NSImage) {
        guard let tiff = image.tiffRepresentation else {
            self.document = AnnotationDocument(imageData: Data(), canvasSize: .zero)
            super.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
            return
        }
        self.document = AnnotationDocument(imageData: tiff, canvasSize: image.size)

        let contentSize = NSSize(
            width: min(image.size.width + 40, 1200),
            height: min(image.size.height + 100, 800)
        )

        super.init(contentRect: NSRect(origin: .zero, size: contentSize),
                   styleMask: [.titled, .closable, .resizable, .miniaturizable],
                   backing: .buffered, defer: false)

        title = "Znap — Annotate"
        center()
        isReleasedWhenClosed = false
        minSize = NSSize(width: 400, height: 300)

        let editorView = AnnotationEditorView(document: document)
        contentView = NSHostingView(rootView: editorView)
    }

    static func open(with image: NSImage) {
        let window = AnnotationEditorWindow(image: image)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

**Step 2: Write AnnotationEditorView (SwiftUI root)**

```swift
import SwiftUI

struct AnnotationEditorView: View {
    @State var document: AnnotationDocument
    @State private var selectedTool: AnnotationDocument.AnnotationType = .arrow
    @State private var selectedColor: Color = .red
    @State private var strokeWidth: CGFloat = 2
    @State private var undoStack: [[AnnotationDocument.Annotation]] = []
    @State private var redoStack: [[AnnotationDocument.Annotation]] = []

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            AnnotationToolbar(
                selectedTool: $selectedTool,
                selectedColor: $selectedColor,
                strokeWidth: $strokeWidth,
                onUndo: undo,
                onRedo: redo,
                onSave: save,
                onCopy: copyToClipboard,
                canUndo: !undoStack.isEmpty,
                canRedo: !redoStack.isEmpty
            )

            Divider()

            // Canvas
            ScrollView([.horizontal, .vertical]) {
                AnnotationCanvasView(
                    document: $document,
                    selectedTool: selectedTool,
                    selectedColor: selectedColor,
                    strokeWidth: strokeWidth,
                    onAnnotationAdded: pushUndo
                )
                .frame(width: document.canvasSize.width, height: document.canvasSize.height)
            }
        }
    }

    private func pushUndo() {
        undoStack.append(document.annotations)
        redoStack.removeAll()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document.annotations)
        document.annotations = previous
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document.annotations)
        document.annotations = next
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "Znap-annotated.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let rendered = renderFinalImage() else { return }
        try? rendered.write(to: url)
    }

    private func copyToClipboard() {
        guard let data = renderFinalImage(),
              let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    private func renderFinalImage() -> Data? {
        // Render annotations on top of base image
        guard let baseImage = NSImage(data: document.imageData) else { return nil }
        let size = document.canvasSize

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        baseImage.draw(in: NSRect(origin: .zero, size: size))
        for annotation in document.annotations {
            AnnotationRenderer.draw(annotation, in: ctx.cgContext)
        }

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
```

**Step 3: Write AnnotationCanvasView (SwiftUI Canvas)**

```swift
import SwiftUI

struct AnnotationCanvasView: View {
    @Binding var document: AnnotationDocument
    let selectedTool: AnnotationDocument.AnnotationType
    let selectedColor: Color
    let strokeWidth: CGFloat
    var onAnnotationAdded: () -> Void

    @State private var currentDragStart: CGPoint?
    @State private var currentDragEnd: CGPoint?
    @State private var currentPencilPoints: [CGPoint] = []

    var body: some View {
        Canvas { context, size in
            // Draw base image
            if let nsImage = NSImage(data: document.imageData) {
                context.draw(Image(nsImage: nsImage), in: CGRect(origin: .zero, size: size))
            }
            // Draw committed annotations
            for annotation in document.annotations {
                drawAnnotation(annotation, in: &context)
            }
            // Draw in-progress annotation
            if let start = currentDragStart, let end = currentDragEnd {
                let inProgress = makeAnnotation(from: start, to: end)
                drawAnnotation(inProgress, in: &context)
            }
        }
        .gesture(dragGesture)
        .frame(width: document.canvasSize.width, height: document.canvasSize.height)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if currentDragStart == nil { currentDragStart = value.startLocation }
                currentDragEnd = value.location
                if selectedTool == .pencil || selectedTool == .highlighter {
                    currentPencilPoints.append(value.location)
                }
            }
            .onEnded { value in
                guard let start = currentDragStart else { return }
                onAnnotationAdded()
                var annotation = makeAnnotation(from: start, to: value.location)
                if selectedTool == .pencil || selectedTool == .highlighter {
                    annotation.points = currentPencilPoints
                }
                document.annotations.append(annotation)
                currentDragStart = nil
                currentDragEnd = nil
                currentPencilPoints = []
            }
    }

    private func makeAnnotation(from start: CGPoint, to end: CGPoint) -> AnnotationDocument.Annotation {
        let nsColor = NSColor(selectedColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)

        return AnnotationDocument.Annotation(
            id: UUID(), type: selectedTool, startPoint: start, endPoint: end,
            points: selectedTool == .pencil || selectedTool == .highlighter ? currentPencilPoints : nil,
            color: AnnotationDocument.CodableColor(red: r, green: g, blue: b, alpha: a),
            strokeWidth: strokeWidth, text: nil, fontSize: nil, counterValue: nil,
            isFilled: selectedTool == .filledRectangle
        )
    }

    private func drawAnnotation(_ annotation: AnnotationDocument.Annotation, in context: inout GraphicsContext) {
        let color = Color(red: annotation.color.red, green: annotation.color.green,
                         blue: annotation.color.blue, opacity: annotation.color.alpha)

        switch annotation.type {
        case .arrow:
            var path = Path()
            path.move(to: annotation.startPoint)
            path.addLine(to: annotation.endPoint)
            context.stroke(path, with: .color(color), lineWidth: annotation.strokeWidth)
            // Arrowhead
            let angle = atan2(annotation.endPoint.y - annotation.startPoint.y,
                            annotation.endPoint.x - annotation.startPoint.x)
            let headLength: CGFloat = 15
            var head = Path()
            head.move(to: annotation.endPoint)
            head.addLine(to: CGPoint(x: annotation.endPoint.x - headLength * cos(angle - .pi / 6),
                                     y: annotation.endPoint.y - headLength * sin(angle - .pi / 6)))
            head.move(to: annotation.endPoint)
            head.addLine(to: CGPoint(x: annotation.endPoint.x - headLength * cos(angle + .pi / 6),
                                     y: annotation.endPoint.y - headLength * sin(angle + .pi / 6)))
            context.stroke(head, with: .color(color), lineWidth: annotation.strokeWidth)

        case .rectangle, .filledRectangle:
            let rect = CGRect(x: min(annotation.startPoint.x, annotation.endPoint.x),
                            y: min(annotation.startPoint.y, annotation.endPoint.y),
                            width: abs(annotation.endPoint.x - annotation.startPoint.x),
                            height: abs(annotation.endPoint.y - annotation.startPoint.y))
            if annotation.isFilled {
                context.fill(Path(rect), with: .color(color))
            } else {
                context.stroke(Path(rect), with: .color(color), lineWidth: annotation.strokeWidth)
            }

        case .ellipse:
            let rect = CGRect(x: min(annotation.startPoint.x, annotation.endPoint.x),
                            y: min(annotation.startPoint.y, annotation.endPoint.y),
                            width: abs(annotation.endPoint.x - annotation.startPoint.x),
                            height: abs(annotation.endPoint.y - annotation.startPoint.y))
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: annotation.strokeWidth)

        case .line:
            var path = Path()
            path.move(to: annotation.startPoint)
            path.addLine(to: annotation.endPoint)
            context.stroke(path, with: .color(color), lineWidth: annotation.strokeWidth)

        case .pencil, .highlighter:
            guard let points = annotation.points, points.count > 1 else { return }
            var path = Path()
            path.move(to: points[0])
            for i in 1..<points.count {
                path.addLine(to: points[i])
            }
            let opacity: CGFloat = annotation.type == .highlighter ? 0.4 : 1.0
            context.stroke(path, with: .color(color.opacity(opacity)),
                         style: StrokeStyle(lineWidth: annotation.type == .highlighter ? annotation.strokeWidth * 4 : annotation.strokeWidth, lineCap: .round, lineJoin: .round))

        case .text:
            let text = Text(annotation.text ?? "Text")
                .font(.system(size: annotation.fontSize ?? 16))
                .foregroundColor(color)
            context.draw(text, at: annotation.startPoint, anchor: .topLeading)

        case .counter:
            let center = annotation.startPoint
            let radius: CGFloat = 14
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
            let numText = Text("\(annotation.counterValue ?? 1)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            context.draw(numText, at: center, anchor: .center)

        case .pixelate, .blur, .spotlight:
            // These require CIFilter / more complex rendering — placeholder rect for now
            let rect = CGRect(x: min(annotation.startPoint.x, annotation.endPoint.x),
                            y: min(annotation.startPoint.y, annotation.endPoint.y),
                            width: abs(annotation.endPoint.x - annotation.startPoint.x),
                            height: abs(annotation.endPoint.y - annotation.startPoint.y))
            context.stroke(Path(rect), with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
}
```

**Step 4: Write AnnotationToolbar**

```swift
import SwiftUI

struct AnnotationToolbar: View {
    @Binding var selectedTool: AnnotationDocument.AnnotationType
    @Binding var selectedColor: Color
    @Binding var strokeWidth: CGFloat
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onSave: () -> Void
    var onCopy: () -> Void
    var canUndo: Bool
    var canRedo: Bool

    private let tools: [(AnnotationDocument.AnnotationType, String, String)] = [
        (.arrow, "arrow.up.right", "A"),
        (.rectangle, "rectangle", "R"),
        (.filledRectangle, "rectangle.fill", ""),
        (.ellipse, "circle", "E"),
        (.line, "line.diagonal", "L"),
        (.text, "textformat", "T"),
        (.counter, "number.circle", "N"),
        (.pixelate, "mosaic", "X"),
        (.blur, "aqi.medium", "B"),
        (.spotlight, "light.max", "S"),
        (.highlighter, "highlighter", "H"),
        (.pencil, "pencil", "P"),
    ]

    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]

    var body: some View {
        HStack(spacing: 8) {
            // Tools
            ForEach(tools, id: \.0) { tool in
                Button(action: { selectedTool = tool.0 }) {
                    Image(systemName: tool.1)
                        .frame(width: 28, height: 28)
                        .background(selectedTool == tool.0 ? Color.accentColor.opacity(0.3) : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("\(tool.0.rawValue) (\(tool.2))")
            }

            Divider().frame(height: 24)

            // Colors
            ForEach(colors, id: \.self) { color in
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2))
                    .onTapGesture { selectedColor = color }
            }
            ColorPicker("", selection: $selectedColor).labelsHidden().frame(width: 24)

            Divider().frame(height: 24)

            // Stroke width
            Slider(value: $strokeWidth, in: 1...10, step: 1).frame(width: 80)

            Spacer()

            // Actions
            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }.disabled(!canUndo).keyboardShortcut("z")
            Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }.disabled(!canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
            Divider().frame(height: 24)
            Button(action: onCopy) { Image(systemName: "doc.on.doc") }.help("Copy to clipboard")
            Button(action: onSave) { Image(systemName: "square.and.arrow.down") }.help("Save")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
```

**Step 5: Write AnnotationRenderer (for final export)**

Create: `Znap/Sources/UI/AnnotationRenderer.swift`

```swift
import AppKit
import CoreGraphics

enum AnnotationRenderer {
    static func draw(_ annotation: AnnotationDocument.Annotation, in ctx: CGContext) {
        let color = CGColor(red: annotation.color.red, green: annotation.color.green,
                           blue: annotation.color.blue, alpha: annotation.color.alpha)
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(annotation.strokeWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch annotation.type {
        case .arrow:
            ctx.move(to: annotation.startPoint)
            ctx.addLine(to: annotation.endPoint)
            ctx.strokePath()
            let angle = atan2(annotation.endPoint.y - annotation.startPoint.y,
                            annotation.endPoint.x - annotation.startPoint.x)
            let hl: CGFloat = 15
            ctx.move(to: annotation.endPoint)
            ctx.addLine(to: CGPoint(x: annotation.endPoint.x - hl * cos(angle - .pi / 6),
                                    y: annotation.endPoint.y - hl * sin(angle - .pi / 6)))
            ctx.move(to: annotation.endPoint)
            ctx.addLine(to: CGPoint(x: annotation.endPoint.x - hl * cos(angle + .pi / 6),
                                    y: annotation.endPoint.y - hl * sin(angle + .pi / 6)))
            ctx.strokePath()

        case .rectangle:
            let rect = CGRect(x: min(annotation.startPoint.x, annotation.endPoint.x),
                            y: min(annotation.startPoint.y, annotation.endPoint.y),
                            width: abs(annotation.endPoint.x - annotation.startPoint.x),
                            height: abs(annotation.endPoint.y - annotation.startPoint.y))
            ctx.stroke(rect)

        case .filledRectangle:
            let rect = CGRect(x: min(annotation.startPoint.x, annotation.endPoint.x),
                            y: min(annotation.startPoint.y, annotation.endPoint.y),
                            width: abs(annotation.endPoint.x - annotation.startPoint.x),
                            height: abs(annotation.endPoint.y - annotation.startPoint.y))
            ctx.fill(rect)

        case .ellipse:
            let rect = CGRect(x: min(annotation.startPoint.x, annotation.endPoint.x),
                            y: min(annotation.startPoint.y, annotation.endPoint.y),
                            width: abs(annotation.endPoint.x - annotation.startPoint.x),
                            height: abs(annotation.endPoint.y - annotation.startPoint.y))
            ctx.strokeEllipse(in: rect)

        case .line:
            ctx.move(to: annotation.startPoint)
            ctx.addLine(to: annotation.endPoint)
            ctx.strokePath()

        case .pencil, .highlighter:
            guard let points = annotation.points, points.count > 1 else { return }
            if annotation.type == .highlighter {
                ctx.setAlpha(0.4)
                ctx.setLineWidth(annotation.strokeWidth * 4)
            }
            ctx.move(to: points[0])
            for i in 1..<points.count { ctx.addLine(to: points[i]) }
            ctx.strokePath()
            ctx.setAlpha(1.0)

        case .text:
            let text = annotation.text ?? "Text"
            let font = NSFont.systemFont(ofSize: annotation.fontSize ?? 16)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(cgColor: color) ?? .red
            ]
            let nsStr = NSAttributedString(string: text, attributes: attrs)
            let line = CTLineCreateWithAttributedString(nsStr)
            ctx.textPosition = annotation.startPoint
            CTLineDraw(line, ctx)

        case .counter:
            let center = annotation.startPoint
            let radius: CGFloat = 14
            ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            // Draw number in white
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            let numStr = "\(annotation.counterValue ?? 1)" as NSString
            let font = NSFont.boldSystemFont(ofSize: 14)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let size = numStr.size(withAttributes: attrs)
            numStr.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attrs)

        case .pixelate, .blur, .spotlight:
            // Placeholder — will implement with CIFilter in a later refinement
            let rect = CGRect(x: min(annotation.startPoint.x, annotation.endPoint.x),
                            y: min(annotation.startPoint.y, annotation.endPoint.y),
                            width: abs(annotation.endPoint.x - annotation.startPoint.x),
                            height: abs(annotation.endPoint.y - annotation.startPoint.y))
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.stroke(rect)
        }
    }
}
```

**Step 6: Wire QAO click → open annotation editor**

In `QuickAccessOverlay.swift`, update the `.openAnnotate` case:

```swift
case .openAnnotate:
    AnnotationEditorWindow.open(with: capturedImage)
    animateOut()
```

**Step 7: Build and test manually**

Run: `make run`
Expected: Capture area → QAO appears → click thumbnail → Annotation Editor opens with toolbar and drawing tools. Draw arrows, rectangles, etc. Save works.

**Step 8: Commit**

```bash
git add Znap/Sources/Models/AnnotationDocument.swift Znap/Sources/UI/AnnotationEditorWindow.swift \
       Znap/Sources/UI/AnnotationCanvasView.swift Znap/Sources/UI/AnnotationToolbar.swift \
       Znap/Sources/UI/AnnotationRenderer.swift Znap/Sources/UI/QuickAccessOverlay.swift \
       Znap/Tests/AnnotationDocumentTests.swift
git commit -m "feat: add annotation editor with drawing tools, undo/redo, export"
```

### Task 11: Pixelate, blur, spotlight using CIFilter

**Files:**
- Create: `Znap/Sources/Utilities/ImageFilters.swift`
- Modify: `Znap/Sources/UI/AnnotationCanvasView.swift`
- Modify: `Znap/Sources/UI/AnnotationRenderer.swift`

**Step 1: Write ImageFilters utility**

```swift
import CoreImage
import AppKit

enum ImageFilters {
    static func pixelate(image: CGImage, region: CGRect, scale: CGFloat = 20) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let filter = CIFilter(name: "CIPixellate")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(cgPoint: CGPoint(x: region.midX, y: region.midY)), forKey: kCIInputCenterKey)

        guard let output = filter.outputImage else { return nil }
        // Crop to region and composite back
        let cropped = output.cropped(to: region)
        let context = CIContext()
        return context.createCGImage(cropped, from: cropped.extent)
    }

    static func blur(image: CGImage, region: CGRect, radius: CGFloat = 10) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let output = filter.outputImage else { return nil }
        let cropped = output.cropped(to: region)
        let context = CIContext()
        return context.createCGImage(cropped, from: region)
    }

    static func spotlight(image: CGImage, region: CGRect, dimAlpha: CGFloat = 0.6) -> CGImage? {
        // Dim everything outside the region
        let size = CGSize(width: image.width, height: image.height)
        let ctx = CGContext(data: nil, width: image.width, height: image.height,
                           bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: dimAlpha))
        ctx.fill(CGRect(origin: .zero, size: size))
        // Clear the spotlight region to show original
        ctx.clear(region)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        // Re-apply dim overlay but not in spotlight region
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: dimAlpha))
        ctx.addRect(CGRect(origin: .zero, size: size))
        ctx.addRect(region)
        ctx.fillPath(using: .evenOdd)
        return ctx.makeImage()
    }
}
```

**Step 2: Update AnnotationRenderer to use CIFilters for pixelate/blur/spotlight**

Replace the pixelate/blur/spotlight cases in `AnnotationRenderer.draw()`:

```swift
case .pixelate:
    let rect = CGRect(x: min(annotation.startPoint.x, annotation.endPoint.x),
                    y: min(annotation.startPoint.y, annotation.endPoint.y),
                    width: abs(annotation.endPoint.x - annotation.startPoint.x),
                    height: abs(annotation.endPoint.y - annotation.startPoint.y))
    if let baseImage = ctx.makeImage(),
       let pixelated = ImageFilters.pixelate(image: baseImage, region: rect) {
        ctx.draw(pixelated, in: rect)
    }

case .blur:
    let rect = CGRect(x: min(annotation.startPoint.x, annotation.endPoint.x),
                    y: min(annotation.startPoint.y, annotation.endPoint.y),
                    width: abs(annotation.endPoint.x - annotation.startPoint.x),
                    height: abs(annotation.endPoint.y - annotation.startPoint.y))
    if let baseImage = ctx.makeImage(),
       let blurred = ImageFilters.blur(image: baseImage, region: rect) {
        ctx.draw(blurred, in: rect)
    }

case .spotlight:
    let rect = CGRect(x: min(annotation.startPoint.x, annotation.endPoint.x),
                    y: min(annotation.startPoint.y, annotation.endPoint.y),
                    width: abs(annotation.endPoint.x - annotation.startPoint.x),
                    height: abs(annotation.endPoint.y - annotation.startPoint.y))
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
    ctx.addRect(CGRect(origin: .zero, size: CGSize(width: ctx.width, height: ctx.height)))
    ctx.addRect(rect)
    ctx.fillPath(using: .evenOdd)
```

**Step 3: Commit**

```bash
git add Znap/Sources/Utilities/ImageFilters.swift Znap/Sources/UI/AnnotationRenderer.swift Znap/Sources/UI/AnnotationCanvasView.swift
git commit -m "feat: add pixelate, blur, spotlight via CIFilter"
```

---

## Phase 5: Screen Recording

### Task 12: RecordingService — MP4 screen recording

**Files:**
- Create: `Znap/Sources/Services/RecordingService.swift`

**Step 1: Write RecordingService**

```swift
import ScreenCaptureKit
import AVFoundation
import AppKit

@MainActor
final class RecordingService: NSObject, ObservableObject {
    static let shared = RecordingService()

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var elapsedTime: TimeInterval = 0

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    private var outputURL: URL?
    private var timer: Timer?
    private var recordingStartDate: Date?

    struct RecordingConfig {
        var rect: CGRect?
        var windowID: CGWindowID?
        var displayID: CGDirectDisplayID?
        var fps: Int = 30
        var captureAudio: Bool = false
        var captureMic: Bool = false
        var showCursor: Bool = true
        var outputAsGIF: Bool = false
    }

    func startRecording(config: RecordingConfig) async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { throw CaptureService.CaptureError.noDisplay }

        let filter: SCContentFilter
        if let windowID = config.windowID,
           let window = content.windows.first(where: { $0.windowID == windowID }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        let streamConfig = SCStreamConfiguration()
        if let rect = config.rect {
            let scale = CGFloat(display.width) / display.frame.width
            streamConfig.sourceRect = CGRect(x: (rect.origin.x - display.frame.origin.x) * scale,
                                             y: (rect.origin.y - display.frame.origin.y) * scale,
                                             width: rect.width * scale, height: rect.height * scale)
            streamConfig.width = Int(rect.width * scale)
            streamConfig.height = Int(rect.height * scale)
        } else {
            streamConfig.width = display.width
            streamConfig.height = display.height
        }
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        streamConfig.showsCursor = config.showCursor
        streamConfig.capturesAudio = config.captureAudio

        // Setup AVAssetWriter
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "znap-recording-\(Int(Date().timeIntervalSince1970)).mp4"
        outputURL = tempDir.appendingPathComponent(filename)
        assetWriter = try AVAssetWriter(outputURL: outputURL!, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: streamConfig.width,
            AVVideoHeightKey: streamConfig.height,
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput!.expectsMediaDataInRealTime = true
        assetWriter!.add(videoInput!)

        if config.captureAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
            ]
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput!.expectsMediaDataInRealTime = true
            assetWriter!.add(audioInput!)
        }

        assetWriter!.startWriting()
        assetWriter!.startSession(atSourceTime: .zero)

        let streamOutput = RecordingStreamOutput(service: self)
        stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        try stream!.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        if config.captureAudio {
            try stream!.addStreamOutput(streamOutput, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        }
        try await stream!.startCapture()

        isRecording = true
        isPaused = false
        recordingStartDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartDate, !self.isPaused else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
        }
    }

    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        try? await stream?.stopCapture()
        stream = nil

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        await assetWriter?.finishWriting()

        timer?.invalidate()
        isRecording = false
        isPaused = false
        elapsedTime = 0

        return outputURL
    }

    func togglePause() {
        isPaused.toggle()
    }

    fileprivate func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer, ofType type: SCStreamOutputType) {
        guard isRecording, !isPaused else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        if startTime == nil {
            startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        }

        switch type {
        case .screen:
            if videoInput?.isReadyForMoreMediaData == true {
                videoInput?.append(sampleBuffer)
            }
        case .audio:
            if audioInput?.isReadyForMoreMediaData == true {
                audioInput?.append(sampleBuffer)
            }
        @unknown default: break
        }
    }
}

private final class RecordingStreamOutput: NSObject, SCStreamOutput {
    weak var service: RecordingService?
    init(service: RecordingService) { self.service = service }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        Task { @MainActor in
            service?.handleSampleBuffer(sampleBuffer, ofType: type)
        }
    }
}
```

**Step 2: Add recording hotkey in AppDelegate**

```swift
// Cmd+Shift+R for recording
HotkeyService.shared.register(
    keyCode: UInt32(kVK_ANSI_R),
    modifiers: UInt32(cmdKey | shiftKey),
    handler: { [weak self] in self?.toggleRecording() }
)

func toggleRecording() {
    if RecordingService.shared.isRecording {
        Task {
            if let url = await RecordingService.shared.stopRecording() {
                let nsImage = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Recording")!
                // Show QAO with video thumbnail (use first frame in production)
                QuickAccessOverlay.show(image: nsImage)
                NSWorkspace.shared.open(url) // Open in QuickTime for now
            }
        }
    } else {
        OverlayWindow.beginAreaSelection { rect in
            guard let rect = rect else { return }
            NSCursor.pop()
            Task {
                let config = RecordingService.RecordingConfig(rect: rect, fps: 30, captureAudio: true)
                try await RecordingService.shared.startRecording(config: config)
            }
        }
    }
}
```

**Step 3: Commit**

```bash
git add Znap/Sources/Services/RecordingService.swift Znap/Sources/AppDelegate.swift
git commit -m "feat: add screen recording service with MP4 output via ScreenCaptureKit"
```

### Task 13: GIF encoder

**Files:**
- Create: `Znap/Sources/Utilities/GIFEncoder.swift`
- Create: `Znap/Tests/GIFEncoderTests.swift`

**Step 1: Write GIFEncoder using ImageIO**

```swift
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

final class GIFEncoder {
    static func encode(frames: [CGImage], frameDelay: TimeInterval, outputURL: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            return false
        }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0 // loop forever
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay
            ]
        ]

        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        return CGImageDestinationFinalize(destination)
    }
}
```

**Step 2: Write test**

```swift
import XCTest
@testable import Znap

final class GIFEncoderTests: XCTestCase {
    func testEncodeCreatesValidGIF() throws {
        // Create simple test frames
        let size = CGSize(width: 10, height: 10)
        var frames: [CGImage] = []
        for i in 0..<3 {
            let ctx = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: CGFloat(i) / 3, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
            frames.append(ctx.makeImage()!)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.gif")
        let result = GIFEncoder.encode(frames: frames, frameDelay: 0.1, outputURL: url)
        XCTAssertTrue(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        XCTAssertTrue(data.count > 0)
        // GIF magic bytes
        XCTAssertEqual(Array(data.prefix(3)), [0x47, 0x49, 0x46]) // "GIF"
        try? FileManager.default.removeItem(at: url)
    }
}
```

**Step 3: Run tests**

Run: `make test`
Expected: PASS

**Step 4: Commit**

```bash
git add Znap/Sources/Utilities/GIFEncoder.swift Znap/Tests/GIFEncoderTests.swift
git commit -m "feat: add GIF encoder using ImageIO"
```

---

## Phase 6: OCR

### Task 14: OCRService

**Files:**
- Create: `Znap/Sources/Services/OCRService.swift`
- Create: `Znap/Tests/OCRServiceTests.swift`

**Step 1: Write OCRService**

```swift
import Vision
import AppKit

final class OCRService {
    static let shared = OCRService()

    func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

**Step 2: Write test**

```swift
import XCTest
@testable import Znap

final class OCRServiceTests: XCTestCase {
    func testRecognizeTextReturnsString() async throws {
        // Create a simple image with text — hard to unit test real OCR without a real image
        // Just verify the service doesn't crash with a blank image
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let image = ctx.makeImage()!

        let result = try await OCRService.shared.recognizeText(in: image)
        // Empty image should return empty string
        XCTAssertTrue(result.isEmpty)
    }
}
```

**Step 3: Wire OCR capture mode in AppDelegate**

```swift
// Cmd+Shift+2 for OCR
HotkeyService.shared.register(
    keyCode: UInt32(kVK_ANSI_2),
    modifiers: UInt32(cmdKey | shiftKey),
    handler: { [weak self] in self?.startOCRCapture() }
)

func startOCRCapture() {
    OverlayWindow.beginAreaSelection { rect in
        guard let rect = rect else { return }
        NSCursor.pop()
        Task {
            do {
                let cgImage = try await CaptureService.shared.captureArea(rect)
                let text = try await OCRService.shared.recognizeText(in: cgImage)
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    // Show notification
                    let notification = NSUserNotification()
                    notification.title = "Text Copied"
                    notification.informativeText = String(text.prefix(100))
                    NSUserNotificationCenter.default.deliver(notification)
                }
            } catch {
                print("OCR failed: \(error)")
            }
        }
    }
}
```

**Step 4: Run tests and commit**

Run: `make test`
Expected: PASS

```bash
git add Znap/Sources/Services/OCRService.swift Znap/Tests/OCRServiceTests.swift Znap/Sources/AppDelegate.swift
git commit -m "feat: add OCR text recognition via Vision framework"
```

---

## Phase 7: Scrolling Capture

### Task 15: ScrollCaptureService + ImageStitcher

**Files:**
- Create: `Znap/Sources/Services/ScrollCaptureService.swift`
- Create: `Znap/Sources/Utilities/ImageStitcher.swift`
- Create: `Znap/Tests/ImageStitcherTests.swift`

**Step 1: Write ImageStitcher**

```swift
import CoreGraphics
import AppKit

enum ImageStitcher {
    /// Stitches images vertically, detecting overlap between consecutive frames
    static func stitch(images: [CGImage]) -> CGImage? {
        guard !images.isEmpty else { return nil }
        guard images.count > 1 else { return images[0] }

        var offsets: [Int] = [0]
        for i in 1..<images.count {
            let overlap = findOverlap(top: images[i - 1], bottom: images[i])
            offsets.append(offsets[i - 1] + images[i - 1].height - overlap)
        }

        let width = images[0].width
        let totalHeight = offsets.last! + images.last!.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(data: nil, width: width, height: totalHeight,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // Draw from bottom to top (CG origin is bottom-left)
        for (i, image) in images.enumerated() {
            let y = totalHeight - offsets[i] - image.height
            ctx.draw(image, in: CGRect(x: 0, y: y, width: image.width, height: image.height))
        }

        return ctx.makeImage()
    }

    /// Find pixel overlap between bottom of `top` image and top of `bottom` image
    private static func findOverlap(top: CGImage, bottom: CGImage, maxSearch: Int = 200) -> Int {
        let width = min(top.width, bottom.width)
        let searchHeight = min(maxSearch, min(top.height, bottom.height))

        guard let topData = top.dataProvider?.data as Data?,
              let bottomData = bottom.dataProvider?.data as Data? else { return 0 }

        let topBytesPerRow = top.bytesPerRow
        let bottomBytesPerRow = bottom.bytesPerRow

        // Compare rows from the bottom of `top` with rows from the top of `bottom`
        for overlap in stride(from: searchHeight, to: 10, by: -1) {
            var match = true
            // Sample every 4th row for speed
            for row in stride(from: 0, to: overlap, by: 4) {
                let topRow = top.height - overlap + row
                let bottomRow = row
                let topOffset = topRow * topBytesPerRow
                let bottomOffset = bottomRow * bottomBytesPerRow
                // Compare middle portion of the row (skip edges which may have scrollbar artifacts)
                let compareStart = width / 4
                let compareEnd = width * 3 / 4
                for x in stride(from: compareStart * 4, to: compareEnd * 4, by: 16) {
                    if topOffset + x + 3 >= topData.count || bottomOffset + x + 3 >= bottomData.count { match = false; break }
                    let diff = abs(Int(topData[topOffset + x]) - Int(bottomData[bottomOffset + x])) +
                               abs(Int(topData[topOffset + x + 1]) - Int(bottomData[bottomOffset + x + 1])) +
                               abs(Int(topData[topOffset + x + 2]) - Int(bottomData[bottomOffset + x + 2]))
                    if diff > 30 { match = false; break }
                }
                if !match { break }
            }
            if match { return overlap }
        }
        return 0
    }
}
```

**Step 2: Write ScrollCaptureService**

```swift
import AppKit
import CoreGraphics

final class ScrollCaptureService {
    static let shared = ScrollCaptureService()

    func captureScrolling(in rect: CGRect, direction: ScrollDirection = .vertical) async throws -> CGImage {
        var frames: [CGImage] = []
        var previousFrameData: Data?
        let maxFrames = 50

        for _ in 0..<maxFrames {
            // Capture current frame
            let frame = try await CaptureService.shared.captureArea(rect)
            let frameData = frame.dataProvider?.data as Data?

            // Check for duplicate (scrolling stopped)
            if let prev = previousFrameData, let curr = frameData, prev == curr {
                break
            }
            previousFrameData = frameData
            frames.append(frame)

            // Send scroll event
            let scrollAmount: Int32 = direction == .vertical ? -5 : 0
            let hScrollAmount: Int32 = direction == .horizontal ? -5 : 0
            let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                       wheelCount: 2, wheel1: scrollAmount, wheel2: hScrollAmount)
            scrollEvent?.post(tap: .cghidEventTap)

            // Wait for scroll to take effect
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }

        guard let stitched = ImageStitcher.stitch(images: frames) else {
            throw CaptureService.CaptureError.captureFailed
        }
        return stitched
    }

    enum ScrollDirection {
        case vertical, horizontal
    }
}
```

**Step 3: Write ImageStitcher test**

```swift
import XCTest
@testable import Znap

final class ImageStitcherTests: XCTestCase {
    func testStitchSingleImage() {
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = ctx.makeImage()!
        let result = ImageStitcher.stitch(images: [image])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 100)
        XCTAssertEqual(result?.height, 100)
    }

    func testStitchEmptyReturnsNil() {
        XCTAssertNil(ImageStitcher.stitch(images: []))
    }
}
```

**Step 4: Wire scrolling capture in AppDelegate**

```swift
// Cmd+Shift+7 for scrolling capture
HotkeyService.shared.register(
    keyCode: UInt32(kVK_ANSI_7),
    modifiers: UInt32(cmdKey | shiftKey),
    handler: { [weak self] in self?.startScrollCapture() }
)

func startScrollCapture() {
    OverlayWindow.beginAreaSelection { rect in
        guard let rect = rect else { return }
        NSCursor.pop()
        Task {
            do {
                let cgImage = try await ScrollCaptureService.shared.captureScrolling(in: rect)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                await MainActor.run { QuickAccessOverlay.show(image: nsImage) }
            } catch {
                print("Scroll capture failed: \(error)")
            }
        }
    }
}
```

**Step 5: Run tests and commit**

Run: `make test`
Expected: PASS

```bash
git add Znap/Sources/Services/ScrollCaptureService.swift Znap/Sources/Utilities/ImageStitcher.swift \
       Znap/Tests/ImageStitcherTests.swift Znap/Sources/AppDelegate.swift
git commit -m "feat: add scrolling capture with auto-scroll and image stitching"
```

---

## Phase 8: Pinned Screenshots

### Task 16: PinnedScreenshotPanel

**Files:**
- Create: `Znap/Sources/UI/PinnedScreenshotPanel.swift`
- Modify: `Znap/Sources/UI/QuickAccessOverlay.swift`

**Step 1: Write PinnedScreenshotPanel**

```swift
import AppKit

final class PinnedScreenshotPanel: NSPanel {
    private static var allPins: [PinnedScreenshotPanel] = []
    private let pinnedImage: NSImage
    private var isLocked = false

    init(image: NSImage) {
        self.pinnedImage = image
        let size = NSSize(width: min(image.size.width, 400), height: min(image.size.height, 400))

        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .transient]
        isMovableByWindowBackground = true
        minSize = NSSize(width: 50, height: 50)

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        contentView = imageView

        center()
        PinnedScreenshotPanel.allPins.append(self)
    }

    // Scroll to adjust opacity
    override func scrollWheel(with event: NSEvent) {
        let delta = event.deltaY * 0.05
        alphaValue = max(0.1, min(1.0, alphaValue - delta))
    }

    // Right-click context menu
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy to Clipboard", action: #selector(copyImage), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Save...", action: #selector(saveImage), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Open in Annotate", action: #selector(openAnnotate), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: isLocked ? "Unlock (Click-through Off)" : "Lock (Click-through On)",
                                action: #selector(toggleLock), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Close", action: #selector(closePin), keyEquivalent: "w"))
        NSMenu.popUpContextMenu(menu, with: event, for: contentView!)
    }

    @objc private func copyImage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([pinnedImage])
    }

    @objc private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Znap-pinned.png"
        guard panel.runModal() == .OK, let url = panel.url,
              let tiff = pinnedImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    @objc private func openAnnotate() {
        AnnotationEditorWindow.open(with: pinnedImage)
        closePin()
    }

    @objc private func toggleLock() {
        isLocked.toggle()
        ignoresMouseEvents = isLocked
    }

    @objc private func closePin() {
        PinnedScreenshotPanel.allPins.removeAll { $0 === self }
        close()
    }

    static func toggleAllVisibility() {
        let shouldHide = allPins.first?.isVisible ?? false
        allPins.forEach { shouldHide ? $0.orderOut(nil) : $0.makeKeyAndOrderFront(nil) }
    }

    static func closeAll() {
        allPins.forEach { $0.close() }
        allPins.removeAll()
    }
}
```

**Step 2: Wire pin action in QAO**

In `QuickAccessOverlay.handleAction()`, update `.pin`:

```swift
case .pin:
    let panel = PinnedScreenshotPanel(image: capturedImage)
    panel.makeKeyAndOrderFront(nil)
    animateOut()
```

**Step 3: Add toggle pins hotkey in AppDelegate**

```swift
// Cmd+Shift+P to toggle all pins
HotkeyService.shared.register(
    keyCode: UInt32(kVK_ANSI_P),
    modifiers: UInt32(cmdKey | shiftKey),
    handler: { PinnedScreenshotPanel.toggleAllVisibility() }
)
```

**Step 4: Commit**

```bash
git add Znap/Sources/UI/PinnedScreenshotPanel.swift Znap/Sources/UI/QuickAccessOverlay.swift Znap/Sources/AppDelegate.swift
git commit -m "feat: add pinned floating screenshots with opacity, lock mode, context menu"
```

---

## Phase 9: All-In-One Mode + Background Tool + History + Desktop Icons + Preferences

### Task 17: All-In-One HUD

**Files:**
- Create: `Znap/Sources/UI/AllInOneHUD.swift`

**Step 1: Write AllInOneHUD**

```swift
import AppKit
import SwiftUI

final class AllInOneHUD: NSPanel {
    private static var current: AllInOneHUD?

    struct Mode: Identifiable {
        let id: String
        let icon: String
        let label: String
        let shortcut: String
        let action: () -> Void
    }

    init(modes: [Mode]) {
        let width: CGFloat = 380
        let height: CGFloat = 70

        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            return
        }

        let origin = NSPoint(x: screen.frame.midX - width / 2, y: screen.frame.midY + 100)
        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .transient]

        let view = NSHostingView(rootView: AllInOneView(modes: modes, onDismiss: { [weak self] in self?.close() }))
        contentView = view
    }

    static func show(with modes: [Mode]) {
        current?.close()
        let hud = AllInOneHUD(modes: modes)
        hud.makeKeyAndOrderFront(nil)
        current = hud
    }

    static func dismiss() {
        current?.close()
        current = nil
    }
}

private struct AllInOneView: View {
    let modes: [AllInOneHUD.Mode]
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(modes) { mode in
                Button(action: { onDismiss(); mode.action() }) {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon).font(.system(size: 22))
                        Text(mode.label).font(.system(size: 10))
                    }
                    .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .help("\(mode.label) (\(mode.shortcut))")
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
```

**Step 2: Wire in AppDelegate**

```swift
// Cmd+Shift+1 for All-In-One
HotkeyService.shared.register(
    keyCode: UInt32(kVK_ANSI_1),
    modifiers: UInt32(cmdKey | shiftKey),
    handler: { [weak self] in self?.showAllInOne() }
)

func showAllInOne() {
    AllInOneHUD.show(with: [
        .init(id: "area", icon: "rectangle.dashed", label: "Area", shortcut: "⌘⇧4") { [weak self] in self?.startAreaCapture() },
        .init(id: "window", icon: "macwindow", label: "Window", shortcut: "⌘⇧5") { [weak self] in self?.startWindowCapture() },
        .init(id: "full", icon: "rectangle.fill", label: "Full", shortcut: "⌘⇧3") { [weak self] in self?.startFullscreenCapture() },
        .init(id: "scroll", icon: "arrow.up.and.down.text.horizontal", label: "Scroll", shortcut: "⌘⇧7") { [weak self] in self?.startScrollCapture() },
        .init(id: "record", icon: "record.circle", label: "Record", shortcut: "⌘⇧R") { [weak self] in self?.toggleRecording() },
        .init(id: "ocr", icon: "text.viewfinder", label: "OCR", shortcut: "⌘⇧2") { [weak self] in self?.startOCRCapture() },
    ])
}
```

**Step 3: Commit**

```bash
git add Znap/Sources/UI/AllInOneHUD.swift Znap/Sources/AppDelegate.swift
git commit -m "feat: add All-In-One HUD mode selector"
```

### Task 18: Background tool

**Files:**
- Create: `Znap/Sources/Utilities/BackgroundRenderer.swift`
- Create: `Znap/Sources/UI/BackgroundToolView.swift`

**Step 1: Write BackgroundRenderer**

```swift
import CoreImage
import AppKit

enum BackgroundRenderer {
    struct Config {
        var backgroundType: BackgroundType = .gradient(preset: 0)
        var padding: CGFloat = 40
        var cornerRadius: CGFloat = 10
        var addShadow: Bool = true
        var aspectRatio: AspectRatio? = nil
    }

    enum BackgroundType {
        case gradient(preset: Int)
        case solid(NSColor)
        case image(NSImage)
    }

    enum AspectRatio: String, CaseIterable {
        case free = "Free"
        case square = "1:1"
        case fourThree = "4:3"
        case sixteenNine = "16:9"
        case nineSixteen = "9:16"

        var ratio: CGFloat? {
            switch self {
            case .free: return nil
            case .square: return 1.0
            case .fourThree: return 4.0 / 3.0
            case .sixteenNine: return 16.0 / 9.0
            case .nineSixteen: return 9.0 / 16.0
            }
        }
    }

    static let gradientPresets: [(NSColor, NSColor)] = [
        (.systemBlue, .systemPurple),
        (.systemPink, .systemOrange),
        (.systemGreen, .systemTeal),
        (.systemIndigo, .systemPurple),
        (.systemOrange, .systemYellow),
        (.systemTeal, .systemCyan),
        (.systemRed, .systemPink),
        (.darkGray, .black),
        (.systemMint, .systemGreen),
        (.systemPurple, .systemPink),
    ]

    static func render(screenshot: NSImage, config: Config) -> NSImage? {
        let imgSize = screenshot.size
        var canvasSize = NSSize(width: imgSize.width + config.padding * 2,
                                height: imgSize.height + config.padding * 2)

        // Apply aspect ratio
        if let ratio = config.aspectRatio?.ratio {
            if canvasSize.width / canvasSize.height > ratio {
                canvasSize.height = canvasSize.width / ratio
            } else {
                canvasSize.width = canvasSize.height * ratio
            }
        }

        let result = NSImage(size: canvasSize)
        result.lockFocus()

        // Draw background
        switch config.backgroundType {
        case .gradient(let preset):
            let (c1, c2) = gradientPresets[preset % gradientPresets.count]
            let gradient = NSGradient(starting: c1, ending: c2)!
            gradient.draw(in: NSRect(origin: .zero, size: canvasSize), angle: 135)

        case .solid(let color):
            color.setFill()
            NSRect(origin: .zero, size: canvasSize).fill()

        case .image(let bgImage):
            bgImage.draw(in: NSRect(origin: .zero, size: canvasSize))
        }

        // Draw screenshot centered with rounded corners and shadow
        let imgRect = NSRect(
            x: (canvasSize.width - imgSize.width) / 2,
            y: (canvasSize.height - imgSize.height) / 2,
            width: imgSize.width, height: imgSize.height
        )

        if config.addShadow {
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 0, height: -4)
            shadow.shadowBlurRadius = 20
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.set()
        }

        let path = NSBezierPath(roundedRect: imgRect, xRadius: config.cornerRadius, yRadius: config.cornerRadius)
        path.addClip()
        screenshot.draw(in: imgRect)

        result.unlockFocus()
        return result
    }
}
```

**Step 2: Write BackgroundToolView (SwiftUI panel in annotation editor)**

```swift
import SwiftUI

struct BackgroundToolView: View {
    let sourceImage: NSImage
    var onApply: (NSImage) -> Void

    @State private var selectedPreset = 0
    @State private var padding: CGFloat = 40
    @State private var cornerRadius: CGFloat = 10
    @State private var addShadow = true
    @State private var aspectRatio: BackgroundRenderer.AspectRatio = .free

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background").font(.headline)

            // Gradient presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<BackgroundRenderer.gradientPresets.count, id: \.self) { i in
                        let (c1, c2) = BackgroundRenderer.gradientPresets[i]
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [Color(nsColor: c1), Color(nsColor: c2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedPreset == i ? Color.white : Color.clear, lineWidth: 2))
                            .onTapGesture { selectedPreset = i }
                    }
                }
            }

            // Padding
            HStack {
                Text("Padding")
                Slider(value: $padding, in: 0...100, step: 5)
                Text("\(Int(padding))px").monospacedDigit()
            }

            // Corner radius
            HStack {
                Text("Corners")
                Slider(value: $cornerRadius, in: 0...30, step: 2)
                Text("\(Int(cornerRadius))px").monospacedDigit()
            }

            Toggle("Shadow", isOn: $addShadow)

            // Aspect ratio
            Picker("Aspect", selection: $aspectRatio) {
                ForEach(BackgroundRenderer.AspectRatio.allCases, id: \.self) { ratio in
                    Text(ratio.rawValue).tag(ratio)
                }
            }.pickerStyle(.segmented)

            Button("Apply") {
                let config = BackgroundRenderer.Config(
                    backgroundType: .gradient(preset: selectedPreset),
                    padding: padding, cornerRadius: cornerRadius,
                    addShadow: addShadow, aspectRatio: aspectRatio
                )
                if let result = BackgroundRenderer.render(screenshot: sourceImage, config: config) {
                    onApply(result)
                }
            }.buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 260)
    }
}
```

**Step 3: Commit**

```bash
git add Znap/Sources/Utilities/BackgroundRenderer.swift Znap/Sources/UI/BackgroundToolView.swift
git commit -m "feat: add background tool with gradient presets, padding, shadow"
```

### Task 19: Capture History (SwiftData)

**Files:**
- Create: `Znap/Sources/Models/CaptureItem.swift`
- Create: `Znap/Sources/Services/HistoryService.swift`

**Step 1: Write CaptureItem model**

```swift
import SwiftData
import Foundation

@Model
final class CaptureItem {
    var id: UUID
    var timestamp: Date
    var captureType: String  // "area", "window", "fullscreen", "scroll", "recording", "ocr"
    var filePath: String?
    var thumbnailData: Data?
    var width: Int
    var height: Int
    var fileSize: Int64

    init(captureType: String, filePath: String?, thumbnailData: Data?, width: Int, height: Int, fileSize: Int64) {
        self.id = UUID()
        self.timestamp = Date()
        self.captureType = captureType
        self.filePath = filePath
        self.thumbnailData = thumbnailData
        self.width = width
        self.height = height
        self.fileSize = fileSize
    }
}
```

**Step 2: Write HistoryService**

```swift
import SwiftData
import AppKit

@MainActor
final class HistoryService {
    static let shared = HistoryService()

    let container: ModelContainer
    let context: ModelContext

    private init() {
        let schema = Schema([CaptureItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    func addCapture(type: String, image: NSImage, filePath: String? = nil) {
        let thumbnail = image.resized(to: NSSize(width: 120, height: 120 * image.size.height / image.size.width))
        let item = CaptureItem(
            captureType: type,
            filePath: filePath,
            thumbnailData: thumbnail?.tiffRepresentation,
            width: Int(image.size.width),
            height: Int(image.size.height),
            fileSize: 0
        )
        context.insert(item)
        try? context.save()
    }

    func recentCaptures(limit: Int = 50) -> [CaptureItem] {
        let descriptor = FetchDescriptor<CaptureItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return (try? context.fetch(descriptor))?.prefix(limit).map { $0 } ?? []
    }

    func cleanup(olderThan days: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let descriptor = FetchDescriptor<CaptureItem>(predicate: #Predicate { $0.timestamp < cutoff })
        if let old = try? context.fetch(descriptor) {
            old.forEach { context.delete($0) }
            try? context.save()
        }
    }
}

extension NSImage {
    func resized(to newSize: NSSize) -> NSImage? {
        let img = NSImage(size: newSize)
        img.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize))
        img.unlockFocus()
        return img
    }
}
```

**Step 3: Commit**

```bash
git add Znap/Sources/Models/CaptureItem.swift Znap/Sources/Services/HistoryService.swift
git commit -m "feat: add capture history with SwiftData storage"
```

### Task 20: Hide desktop icons

**Files:**
- Create: `Znap/Sources/Utilities/DesktopIconManager.swift`

**Step 1: Write DesktopIconManager**

```swift
import Foundation

final class DesktopIconManager {
    static let shared = DesktopIconManager()
    private var wereHidden = false

    func hideIcons() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", "false"]
        try? task.run()
        task.waitUntilExit()
        restartFinder()
        wereHidden = true
    }

    func showIcons() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", "true"]
        try? task.run()
        task.waitUntilExit()
        restartFinder()
        wereHidden = false
    }

    func restoreIfNeeded() {
        if wereHidden { showIcons() }
    }

    private func restartFinder() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Finder"]
        try? task.run()
    }
}
```

**Step 2: Add cleanup on app termination in AppDelegate**

```swift
func applicationWillTerminate(_ notification: Notification) {
    DesktopIconManager.shared.restoreIfNeeded()
}
```

**Step 3: Commit**

```bash
git add Znap/Sources/Utilities/DesktopIconManager.swift Znap/Sources/AppDelegate.swift
git commit -m "feat: add desktop icon hide/show with auto-restore on quit"
```

### Task 21: Preferences panel

**Files:**
- Create: `Znap/Sources/Models/Preferences.swift`
- Create: `Znap/Sources/UI/PreferencesView.swift`

**Step 1: Write Preferences model**

```swift
import SwiftUI

final class ZnapPreferences: ObservableObject {
    static let shared = ZnapPreferences()

    @AppStorage("defaultSaveLocation") var defaultSaveLocation: String = "~/Desktop"
    @AppStorage("defaultFormat") var defaultFormat: String = "png"
    @AppStorage("jpegQuality") var jpegQuality: Double = 0.85
    @AppStorage("qaoAutoDismiss") var qaoAutoDismiss: Double = 15
    @AppStorage("qaoPosition") var qaoPosition: String = "bottomRight"
    @AppStorage("includeWindowShadow") var includeWindowShadow: Bool = true
    @AppStorage("autoHideDesktopIcons") var autoHideDesktopIcons: Bool = false
    @AppStorage("historyRetentionDays") var historyRetentionDays: Int = 30
    @AppStorage("recordingFPS") var recordingFPS: Int = 30
    @AppStorage("recordingFormat") var recordingFormat: String = "mp4"
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
}
```

**Step 2: Write PreferencesView**

```swift
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var prefs = ZnapPreferences.shared

    var body: some View {
        TabView {
            GeneralTab(prefs: prefs).tabItem { Label("General", systemImage: "gear") }
            CaptureTab(prefs: prefs).tabItem { Label("Capture", systemImage: "camera") }
            RecordingTab(prefs: prefs).tabItem { Label("Recording", systemImage: "record.circle") }
        }
        .frame(width: 450, height: 300)
        .padding()
    }
}

private struct GeneralTab: View {
    @ObservedObject var prefs: ZnapPreferences
    var body: some View {
        Form {
            TextField("Save Location", text: $prefs.defaultSaveLocation)
            Picker("Default Format", selection: $prefs.defaultFormat) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpeg")
                Text("WebP").tag("webp")
            }
            if prefs.defaultFormat == "jpeg" {
                Slider(value: $prefs.jpegQuality, in: 0.1...1.0, step: 0.05) {
                    Text("JPEG Quality: \(Int(prefs.jpegQuality * 100))%")
                }
            }
            Stepper("History retention: \(prefs.historyRetentionDays) days", value: $prefs.historyRetentionDays, in: 1...365)
            Toggle("Launch at Login", isOn: $prefs.launchAtLogin)
        }
    }
}

private struct CaptureTab: View {
    @ObservedObject var prefs: ZnapPreferences
    var body: some View {
        Form {
            Picker("QAO Auto-dismiss", selection: $prefs.qaoAutoDismiss) {
                Text("5 seconds").tag(5.0)
                Text("15 seconds").tag(15.0)
                Text("30 seconds").tag(30.0)
                Text("Never").tag(0.0)
            }
            Toggle("Include Window Shadow", isOn: $prefs.includeWindowShadow)
            Toggle("Auto-hide Desktop Icons", isOn: $prefs.autoHideDesktopIcons)
        }
    }
}

private struct RecordingTab: View {
    @ObservedObject var prefs: ZnapPreferences
    var body: some View {
        Form {
            Picker("Default FPS", selection: $prefs.recordingFPS) {
                Text("15").tag(15)
                Text("30").tag(30)
                Text("60").tag(60)
            }
            Picker("Default Format", selection: $prefs.recordingFormat) {
                Text("MP4").tag("mp4")
                Text("GIF").tag("gif")
            }
        }
    }
}
```

**Step 3: Add preferences to menu bar**

In `ZnapApp.swift`, add:
```swift
Settings {
    PreferencesView()
}
```

And add a menu bar button:
```swift
Button("Preferences...") {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}
.keyboardShortcut(",")
```

**Step 4: Commit**

```bash
git add Znap/Sources/Models/Preferences.swift Znap/Sources/UI/PreferencesView.swift Znap/Sources/ZnapApp.swift
git commit -m "feat: add preferences panel with general, capture, recording tabs"
```

### Task 22: Final menu bar + create-dmg script

**Files:**
- Modify: `Znap/Sources/ZnapApp.swift` (final menu bar with all modes)
- Create: `scripts/create-dmg.sh`

**Step 1: Update ZnapApp.swift with complete menu bar**

```swift
import SwiftUI

@main
struct ZnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Znap", systemImage: "camera.viewfinder") {
            Button("All-In-One (⌘⇧1)") { appDelegate.showAllInOne() }
            Divider()
            Button("Capture Area (⌘⇧4)") { appDelegate.startAreaCapture() }
            Button("Capture Fullscreen (⌘⇧3)") { appDelegate.startFullscreenCapture() }
            Button("Capture Window (⌘⇧5)") { appDelegate.startWindowCapture() }
            Button("Freeze & Capture (⌘⇧6)") { appDelegate.startFreezeCapture() }
            Button("Scrolling Capture (⌘⇧7)") { appDelegate.startScrollCapture() }
            Divider()
            Button("Record Screen (⌘⇧R)") { appDelegate.toggleRecording() }
            Button("OCR Text (⌘⇧2)") { appDelegate.startOCRCapture() }
            Divider()
            Button("Toggle Desktop Icons") { DesktopIconManager.shared.hideIcons() }
            Button("Show/Hide Pins (⌘⇧P)") { PinnedScreenshotPanel.toggleAllVisibility() }
            Divider()
            // Recent captures submenu
            Menu("Recent Captures") {
                ForEach(HistoryService.shared.recentCaptures(limit: 10), id: \.id) { item in
                    Button("\(item.captureType) — \(item.timestamp.formatted())") {
                        // Re-open logic
                    }
                }
                if HistoryService.shared.recentCaptures(limit: 1).isEmpty {
                    Text("No recent captures")
                }
            }
            Divider()
            Button("Preferences...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }.keyboardShortcut(",")
            Button("Quit Znap") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings {
            PreferencesView()
        }
    }
}
```

**Step 2: Write create-dmg.sh**

```bash
#!/bin/bash
set -euo pipefail

APP_NAME="Znap"
BUILD_DIR="build/Build/Products/Release"
DMG_NAME="${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"
STAGING_DIR=$(mktemp -d)

echo "Creating DMG..."

# Copy app to staging
cp -R "${BUILD_DIR}/${APP_NAME}.app" "${STAGING_DIR}/"

# Create symlink to Applications
ln -s /Applications "${STAGING_DIR}/Applications"

# Create DMG
hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO "${DMG_NAME}"

# Cleanup
rm -rf "${STAGING_DIR}"

echo "Created ${DMG_NAME}"
```

**Step 3: Make script executable and test**

```bash
chmod +x scripts/create-dmg.sh
make dmg
```

Expected: `Znap.dmg` created in project root.

**Step 4: Final commit**

```bash
git add scripts/create-dmg.sh Znap/Sources/ZnapApp.swift
git commit -m "feat: complete menu bar, add create-dmg script"
```

---

## Hotkey Summary

| Shortcut | Action |
|----------|--------|
| ⌘⇧1 | All-In-One mode selector |
| ⌘⇧2 | OCR text capture |
| ⌘⇧3 | Fullscreen capture |
| ⌘⇧4 | Area capture |
| ⌘⇧5 | Window capture |
| ⌘⇧6 | Freeze screen + capture |
| ⌘⇧7 | Scrolling capture |
| ⌘⇧R | Start/stop recording |
| ⌘⇧P | Toggle pinned screenshots |

---

## Build & Install

```bash
# Prerequisites
brew install xcodegen

# Build
make build

# Run (debug)
make run

# Install to /Applications
make install

# Create DMG
make dmg

# Run tests
make test
```
