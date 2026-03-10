# Znap — Product Spec

## Overview

Znap is a lightweight, all-in-one macOS screenshot and screen recording tool. It lives in the menu bar and provides instant access to capture, annotate, record, and share screen content.

**Bundle ID:** `com.znap.app`
**Min macOS:** 13.0
**Architecture:** Universal (arm64 + x86_64)
**Distribution:** Direct (Sparkle auto-update), planned App Store
**Pricing:** Free (planned freemium)

## Core Value Proposition

The aesthetic polish and reliability of CleanShot X with built-in video editing, a transparent pricing model, and no proprietary cloud lock-in.

## Target Users

- Developers sharing code snippets, bug reports, UI issues
- Designers capturing and annotating UI references
- Product managers creating tutorials and documentation
- Support engineers capturing and redacting sensitive screens

---

## Features

### Capture Modes

| Feature | Shortcut | Status | Description |
|---------|----------|--------|-------------|
| All-In-One HUD | Cmd+Shift+1 | Done | Radial menu for quick mode selection |
| Area Capture | Cmd+Shift+4 | Done | Click-drag rectangle selection with crosshair |
| Fullscreen Capture | Cmd+Shift+3 | Done | Captures entire screen instantly |
| Window Capture | Cmd+Shift+8 | Done | Click a window to capture it (with optional shadow) |
| Freeze & Capture | Cmd+Shift+6 | Done | Freezes screen, then allows area selection on frozen frame |
| OCR Text Capture | Cmd+Shift+2 | Done | Select area, extract text to clipboard via Vision framework |
| Scrolling Capture | Cmd+Shift+7 | Done | Captures content beyond viewport by auto-scrolling and stitching |
| Screen Recording | Cmd+Shift+R | Done | Records screen to MP4 via ScreenCaptureKit + AVAssetWriter |

### Post-Capture Flow

| Feature | Status | Description |
|---------|--------|-------------|
| Quick Access Overlay | Done | Floating thumbnail appears after capture with actions: copy, save, annotate, dismiss |
| Auto-dismiss timer | Done | QAO disappears after configurable timeout (default 15s) |
| Copy to clipboard | Done | One-click copy from QAO or editor |
| Save to file | Done | Save panel with PNG/JPEG format choice |
| Open in editor | Done | Opens annotation editor for markup |

### Annotation Editor

| Feature | Status | Description |
|---------|--------|-------------|
| Arrow tool | Done | Curved/straight arrows with drag handles |
| Rectangle tool | Done | Outlined or filled rectangles |
| Circle/Ellipse tool | Done | Outlined or filled ellipses |
| Line tool | Done | Straight lines |
| Pencil/freehand | Done | Smooth freehand drawing with path simplification |
| Highlighter | Done | Semi-transparent freehand highlighting |
| Text tool | Done | Click-to-place text with font size control |
| Handwriting tool | Done | Indie Flower font handwriting style |
| Counter/step tool | Done | Auto-incrementing numbered circles (1, 2, 3...) |
| Pixelate region | Done | Mosaic pixelation of selected area |
| Blur region | Done | Gaussian blur of selected area |
| Spotlight | Done | Dims everything except selected area |
| Color picker | Done | Per-annotation color selection (persisted) |
| Stroke width | Done | Adjustable stroke width |
| Undo/redo | Done | Full undo/redo stack |
| Selection & move | Done | Click to select, drag to move annotations |
| Resize handles | Done | Drag corners/edges to resize |
| Arrow curve handle | Done | Drag to curve arrows, double-click to reset |
| Zoom | Done | Pinch/scroll zoom with fit-to-window |
| Background renderer | Done | Gradient/solid backgrounds with padding, corner radius, shadow, window header, aspect ratio presets |

### Screen Recording

| Feature | Status | Description |
|---------|--------|-------------|
| Area/fullscreen recording | Done | Select area or record full screen |
| Recording indicator pill | Done | Floating pill showing elapsed time with pause/stop controls |
| Pause/resume | Done | Toggle recording pause |
| Window exclusion | Done | Recording indicator excluded from capture |
| Video editor | Done | Post-recording editor with trim and split |
| Timeline with segments | Done | Visual filmstrip with draggable split markers |
| Per-segment delete | Done | Mark segments as deleted |
| Video export | Done | Re-export edited video via AVMutableComposition |
| System audio capture | Done | Captures system audio via ScreenCaptureKit |

### Utilities

| Feature | Status | Description |
|---------|--------|-------------|
| OCR (Vision) | Done | Text recognition from captured images |
| History service | Done | Persists captures with metadata, auto-cleanup |
| Hotkey service | Done | Global keyboard shortcuts via Carbon API (customizable per-mode) |
| Desktop icon manager | Done | Hide/show desktop icons programmatically |
| GIF encoder | Done | Utility for GIF encoding (not yet wired to UI) |
| Image stitcher | Done | Stitches scroll capture frames |
| Image filters | Done | Pixelate, blur, spotlight CIFilter wrappers |
| Path smoothing | Done | Ramer-Douglas-Peucker simplification for freehand paths |
| Auto-update | Done | Sparkle framework for update distribution |

### Preferences

| Setting | Default | Description |
|---------|---------|-------------|
| Default save location | ~/Desktop | Where screenshots are saved |
| Launch at login | false | Auto-start on login |
| History retention | 30 days | Auto-cleanup old captures |
| Default format | PNG | PNG or JPEG |
| JPEG quality | 0.85 | Compression quality |
| QAO auto-dismiss | 15s | Quick Access Overlay timeout |
| Include window shadow | true | Capture native macOS shadow |
| Auto-hide desktop icons | false | Hide icons before capture |
| Auto-open editor | false | Skip QAO, go straight to editor |
| Recording FPS | 30 | Frames per second |
| Recording format | MP4 | Output format |
| Per-mode hotkeys | Cmd+Shift+{1-8,R} | Customizable keyboard shortcuts per capture mode |

---

## Architecture

### App Structure
- **ZnapApp.swift** — SwiftUI `@main` entry point with `MenuBarExtra`
- **AppDelegate.swift** — NSApplicationDelegate, owns services and coordinates capture flows
- **LSUIElement = true** — Menu bar only app (no dock icon by default)
- **Activation policy** — Switches to `.regular` when editor is open (CMD+TAB visible)

### Services Layer
- **CaptureService** — ScreenCaptureKit-based screenshot capture
- **RecordingService** — Screen recording via SCStream + AVAssetWriter
- **ScrollCaptureService** — Automated scroll + stitch capture
- **OCRService** — Vision framework text recognition
- **HistoryService** — Persistent capture history with metadata
- **HotkeyService** — Global hotkey registration via Carbon API
- **VideoExportService** — AVMutableComposition-based video re-export

### UI Layer
- **SelectionView** — Area selection overlay with crosshair
- **WindowHighlightOverlay** — Window detection and highlight
- **FreezeScreenOverlay** — Screen freeze for capture
- **QuickAccessOverlay/View** — Post-capture floating thumbnail
- **AnnotationEditorWindow** — NSWindow hosting the editor
- **AnnotationEditorView** — SwiftUI root for annotation editor
- **AnnotationCanvasView** — SwiftUI Canvas for live annotation preview
- **AnnotationToolbar** — Tool/color/action bar
- **AnnotationRenderer** — CoreGraphics-based final image compositing
- **AnnotationHitTesting** — Hit detection for selection/manipulation
- **BackgroundToolView** — Background/wallpaper configuration UI
- **VideoEditorPanel** — NSPanel hosting video editor
- **VideoTimelineView** — NSView timeline with filmstrip and split markers
- **RecordingIndicatorPanel** — Floating recording status pill
- **AllInOneHUD** — Radial mode selector
- **ShortcutRecorderView** — Keyboard shortcut recorder for preferences
- **PreferencesWindow/View** — Settings UI (General, Capture, Recording, Shortcuts tabs)

### Utilities
- **BackgroundRenderer** — Renders screenshot on gradient/solid backgrounds
- **DesktopIconManager** — Hides/shows Finder desktop icons
- **GIFEncoder** — Frame-to-GIF encoding
- **ImageFilters** — CIFilter wrappers (pixelate, blur, spotlight)
- **ImageStitcher** — Vertical image stitching for scroll captures
- **PathSmoothing** — Ramer-Douglas-Peucker path simplification

### Dependencies
- **Sparkle 2.7+** — Auto-update framework
- **ScreenCaptureKit** — Screen capture and recording (macOS 13+)
- **Vision** — OCR text recognition
- **Carbon** — Global hotkey registration

### Build System
- **XcodeGen** (`project.yml`) — Generates Xcode project
- **Makefile** — `make run`, `make build`, `make install`, `make dmg`
