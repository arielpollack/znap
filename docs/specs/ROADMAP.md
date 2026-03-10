# Znap — Roadmap

## Competitive Landscape

| Competitor | Price | Strengths | Weaknesses |
|-----------|-------|-----------|------------|
| CleanShot X | $29/yr | Gold standard UX, cloud upload, hide desktop icons | Subscription pricing, cloud bloat, macOS compat bugs |
| Shottr | Free/paid | Lightweight, pixel measurement, color picker, smart erase | No video recording, nagware, buggy scrolling, looks abandoned |
| ScreenFloat | $16 | Floating shots, powerful library, non-destructive annotations | Resource heavy, gets lost in CMD+TAB, steep learning curve |
| macOS built-in | Free | Zero install, always available | No annotations, no scrolling, no blur/redact, slow workflow |

## Znap's Current Advantages
- Free, no subscription
- All-in-one: screenshot + recording + video editing + annotations
- Background/wallpaper renderer built-in
- Lightweight menu bar app
- Step counter annotations (tutorials)
- Cumulative image filters (blur + pixelate compose correctly)

---

## Priority Features

### Tier 1 — Table Stakes (v0.2)

| # | Feature | Why | Difficulty | Spec Status |
|---|---------|-----|------------|-------------|
| 1 | Per-mode global hotkey customization | Dealbreaker for power users — need separate shortcuts per mode | Medium | Done |
| 2 | Hide desktop icons toggle before capture | CleanShot's #1 loved feature — DesktopIconManager exists, needs UI wiring | Easy | Done |
| 3 | GIF export from recordings | Shottr users' #1 want — GIFEncoder exists, needs UI wiring | Medium | Done |
| 4 | Instant OCR toast (text to clipboard, no image) | Unique differentiator — OCRService exists, needs dedicated flow | Easy | Done |
| 5 | Destination modifiers (Option=desktop, Ctrl=clipboard) | Zero-friction workflow for power users | Medium | Done |
| 6 | Window shadow quick toggle in menu bar | Presentation quality — preference exists but not in menu | Easy | Done |

### Tier 2 — Differentiation (v0.3)

| # | Feature | Why | Difficulty | Spec Status |
|---|---------|-----|------------|-------------|
| 7 | Color picker tool | Developer favorite from Shottr | Easy | Not started |
| 8 | Pixel measurement/ruler | Developer favorite from Shottr | Medium | Not started |
| 9 | Smart redact (auto-detect emails, IPs, API keys) | Premium feature gap in all competitors | Hard | Not started |
| 10 | Annotation improvements: emoji stamps, magnifier | Presentation quality | Medium | Not started |
| 11 | Capture timer/delay | Useful for dropdown menus and tooltips | Easy | Not started |

### Tier 3 — Premium (v0.4+)

| # | Feature | Why | Difficulty | Spec Status |
|---|---------|-----|------------|-------------|
| 12 | BYO cloud upload (S3/custom URL) | CleanShot Cloud alternative without lock-in | Medium | Not started |
| 13 | Cursor zoom replay in recordings | Screen Studio killer feature | Hard | Not started |
| 14 | Non-destructive annotations (edit after save) | ScreenFloat's unique feature | Hard | Not started |
| 15 | Image stitching (combine multiple screenshots) | User request across all competitors | Medium | Not started |
| 16 | Cross-device sync via iCloud | Premium feature | Hard | Not started |
| 17 | Keystroke/click overlay in recordings | Tutorial creation | Medium | Not started |

---

## Version History

### v0.2.0 (Current)
- Per-mode customizable keyboard shortcuts with recorder UI
- Auto-hide desktop icons during capture
- GIF export from video editor (configurable 5-15 fps)
- Instant OCR toast feedback (replaces system notification)
- Destination modifiers: Option=save, Ctrl=copy, Shift=edit
- Window shadow quick toggle in menu bar
- ToastPanel shared HUD component

### v0.1.0
- Area, fullscreen, window, freeze capture
- Scrolling capture with auto-stitch
- OCR text extraction
- Screen recording with system audio
- Video editor with trim/split
- Full annotation editor (arrows, shapes, text, counters, blur, pixelate, spotlight)
- Background renderer (gradients, solid, shadow, window header, aspect ratios)
- Quick access overlay with auto-dismiss
- Preferences panel
- Sparkle auto-update
- Menu bar app with global hotkeys
- App icon (vibrant blue-purple crosshair)
