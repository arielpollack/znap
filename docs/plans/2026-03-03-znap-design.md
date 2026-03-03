# Znap — macOS Screenshot Replacement

## Overview

Znap is a macOS menu bar app that replaces the native screenshot tool with a CleanShot X-inspired workflow optimized for developer use. Pure Swift, no third-party dependencies, built entirely on Apple frameworks.

**Target:** macOS 13.0+ (Ventura) — required for ScreenCaptureKit's full API
**Distribution:** `.app` bundle via `xcodebuild`, installable via `make install` or `make dmg`
**Stack:** Swift 5.9+, AppKit (system windows), SwiftUI (content views), ScreenCaptureKit, AVFoundation, Vision, Core Image, ImageIO, SwiftData

## Architecture

```
ZnapApp (SwiftUI App, menu bar only — no dock icon)
├── Services/
│   ├── CaptureService          — ScreenCaptureKit wrapper for all capture modes
│   ├── RecordingService        — AVFoundation screen recording + GIF via ImageIO
│   ├── OCRService              — Vision framework text recognition
│   ├── ScrollCaptureService    — CGWindowListCreateImage + auto-scroll + stitch
│   ├── HistoryService          — SwiftData capture log
│   └── HotkeyService           — Carbon/CGEvent global hotkey registration
├── UI/
│   ├── MenuBarView             — SwiftUI MenuBarExtra
│   ├── OverlayWindow           — AppKit NSPanel for capture selection
│   ├── QuickAccessOverlay      — AppKit NSPanel floating thumbnail
│   ├── AnnotationEditor        — SwiftUI Canvas-based annotation view in NSPanel
│   ├── PinnedScreenshot        — AppKit NSPanel always-on-top
│   └── AllInOneHUD             — AppKit NSPanel mode selector
├── Models/
│   ├── CaptureItem             — SwiftData model for history
│   ├── AnnotationDocument      — Codable annotation state
│   └── Preferences             — @AppStorage user preferences
└── Utilities/
    ├── GIFEncoder              — ImageIO CGImageDestination wrapper
    ├── ImageStitcher            — Core Graphics image composition
    ├── DesktopIconManager       — NSWorkspace desktop icon toggle
    └── BackgroundRenderer       — Core Image gradient/solid background compositing
```

### Key Architectural Decisions

- **AppKit for system windows** — floating panels, overlays, capture selection, pinned screenshots. SwiftUI cannot do borderless, transparent, always-on-top, click-through windows.
- **SwiftUI for content** — annotation editor, preferences, menu bar, hosted inside AppKit windows via `NSHostingView`.
- **No third-party dependencies** — everything uses Apple frameworks.
- **SwiftData** for capture history — lightweight, no Core Data boilerplate.
- **Codable** annotation documents for save/restore of annotated screenshots.
- **Non-sandboxed** — required for global hotkeys, CGEvent taps, desktop icon manipulation.

## Feature Design

### Feature 1: Capture Modes

#### Area Capture
- Global hotkey triggers `OverlayWindow` — transparent, full-screen `NSPanel` covering all displays.
- Crosshair cursor with dimension labels (width x height) and magnifier loupe showing pixel-level detail.
- Click-drag to select region, ESC to cancel.
- Hold Shift to lock aspect ratio, hold Space to move selection.
- Uses `ScreenCaptureKit` `SCScreenshotManager.captureImage(...)` with the selected `CGRect`.
- Result flows to Quick Access Overlay.

#### Window Capture
- Same overlay, but hovering over windows highlights them (blue border overlay via `CGWindowListCopyWindowInfo`).
- Click to capture the highlighted window.
- Uses `CGWindowListCreateImage` with the window ID for pixel-perfect window capture including shadow.
- Configurable: include/exclude shadow, custom background color behind window.

#### Fullscreen Capture
- Immediate — captures the current display via ScreenCaptureKit.

#### Scrolling Capture
- User selects a region (like area capture).
- Auto-scrolls by sending scroll events via `CGEvent`.
- Each frame captured via `CGWindowListCreateImage`.
- `ImageStitcher` finds overlap regions using pixel comparison and stitches frames vertically.
- Stops when content stops changing (duplicate frame detection).
- Supports vertical and horizontal scrolling.

#### Freeze Screen
- Before selection, capture all displays and display them as full-screen `NSPanel` windows.
- User selects from the frozen image — useful for tooltips, menus, hover states.

### Feature 2: All-In-One Mode

- Single hotkey opens a small HUD with icons for each mode: Area, Window, Fullscreen, Scrolling, Record, OCR.
- Remembers last capture region (stored in `UserDefaults`).
- Pressing the hotkey again with a saved region re-captures that exact area.
- Each mode also has its own dedicated hotkey.

### Feature 3: Quick Access Overlay (QAO)

The hub of the post-capture workflow. Appears after every capture.

- `NSPanel` with `.floating` level, no title bar, rounded corners.
- Appears in bottom-right corner (configurable position).
- Shows thumbnail of capture + file size + dimensions.
- Actions:
  - **Click** → open in Annotation Editor
  - **Cmd+C** → copy to clipboard
  - **Cmd+S** → save to default location (configurable)
  - **Cmd+Shift+S** → save as (with format picker: PNG/JPEG/WebP)
  - **Cmd+P** → pin to screen
  - **Drag** → drag image into any app (via `NSDraggingSource`)
  - **ESC / Cmd+W** → dismiss
- Auto-dismiss timer (configurable: 5s, 15s, 30s, never).
- Swipe down to hide temporarily.
- "Restore last" hotkey brings back dismissed overlay.

### Feature 4: Annotation Editor

Opens in a new resizable window (`NSPanel` with `NSHostingView` containing SwiftUI `Canvas`).

#### Tools

| Tool | Shortcut | Notes |
|------|----------|-------|
| Arrow | A | Straight + curved variants |
| Rectangle | R | Outline or filled |
| Ellipse | E | Outline or filled |
| Line | L | |
| Text | T | Click to place, configurable font/size/color |
| Counter | N | Auto-incrementing numbered circles |
| Pixelate | X | Randomized mosaic (prevents depixelization) |
| Blur | B | Gaussian blur region |
| Spotlight | S | Dims everything outside selection |
| Highlighter | H | Semi-transparent brush |
| Pencil | P | Freehand with auto-smoothing |
| Crop | C | With aspect ratio lock |

#### Controls
- **Stroke width:** keys 1-5.
- **Colors:** palette bar + system color picker.
- **Undo/Redo:** Cmd+Z / Cmd+Shift+Z (unlimited).
- **Duplicate:** Cmd+D or Option+drag.
- **Export:** Save as PNG/JPEG, copy to clipboard, save as `.znap` (Codable JSON with embedded image data for re-editable annotations).

### Feature 5: Screen Recording

- Triggered from All-In-One or dedicated hotkey.
- Area selection same as screenshot, or choose window/fullscreen.
- Pre-recording options: format (MP4/GIF), FPS (15/30/60), include cursor, include audio (mic/system).
- Recording indicator: red dot in menu bar + elapsed time.
- Controls: pause/resume, stop.
- **Computer audio:** `SCStream` audio capture (ScreenCaptureKit, no extra drivers).
- **Mic audio:** `AVAudioEngine` with input device.
- **Click highlighting:** `CGEvent` tap to detect clicks, render colored circle animation on overlay.
- **Keystroke display:** `CGEvent` tap for key events, render keystroke HUD at bottom of screen.
- **GIF output:** `ImageIO` `CGImageDestination` with `kUTTypeGIF`, frame delay matching FPS.
- Post-recording: simple trim editor (start/end sliders) before saving.
- Result flows to Quick Access Overlay.

### Feature 6: OCR / Text Recognition

- Hotkey triggers area selection.
- `VNRecognizeTextRequest` from Vision framework on the selected region.
- Recognized text copied to clipboard immediately.
- Supports all languages Vision supports (20+).
- Notification banner with preview of extracted text.

### Feature 7: Pinned / Floating Screenshots

- `NSPanel` with `.floating` level, always-on-top.
- Resize by dragging corners.
- Opacity control via two-finger scroll gesture.
- Right-click context menu: Copy, Save, Annotate, OCR, Close.
- Lock mode: `ignoresMouseEvents = true` — clicks pass through to underlying windows.
- Hide/show all pins with a single hotkey.

### Feature 8: Background Tool

Accessible from Annotation Editor toolbar.

- **Gradient backgrounds:** 10 built-in presets (blue→purple, pink→orange, etc.).
- **Solid color** background.
- **Custom image** background.
- **Padding slider:** 0–100px.
- **Auto-balance:** center content with even padding.
- **Aspect ratio presets:** 1:1, 4:3, 16:9, 9:16.
- **Window chrome:** add/remove shadow, adjust rounded corners.
- Implementation: Core Image compositing — render background layer, center screenshot on canvas.

### Feature 9: Hide Desktop Icons

- Uses `defaults write com.apple.finder CreateDesktop -bool false && killall Finder` to hide.
- Toggle before/after capture automatically (configurable in preferences).
- Always restores on app quit (safety net).

### Feature 10: Capture History

- SwiftData store: thumbnail, full image path, timestamp, capture type, dimensions, file size.
- Menu bar dropdown shows recent captures (last 50).
- Click to re-open in QAO or Annotation Editor.
- Auto-cleanup after 30 days (configurable).

## Entitlements

```xml
com.apple.security.screen-recording        — screen capture
com.apple.security.accessibility            — global hotkeys, CGEvent taps
com.apple.security.device.audio-input       — microphone for recordings
```

Non-sandboxed (required for global hotkeys + desktop icon manipulation).

## Build & Install

```
znap/
├── Znap.xcodeproj
├── Znap/
│   ├── ZnapApp.swift
│   ├── Info.plist
│   ├── Znap.entitlements
│   └── ... (source files)
├── Makefile
└── scripts/
    └── create-dmg.sh
```

```bash
make build          # xcodebuild -scheme Znap -configuration Release
make install        # copies Znap.app to /Applications
make dmg            # creates Znap.dmg using create-dmg
make clean          # clean build artifacts
```

## Preferences

All configurable via the menu bar preferences panel:

- Default save location
- Default file format (PNG/JPEG/WebP)
- JPEG quality slider
- Auto-dismiss QAO timer
- QAO position (corner)
- Global hotkeys for each mode
- Include/exclude window shadow
- Auto-hide desktop icons on capture
- Capture history retention period
- Recording defaults (FPS, format, audio sources)
