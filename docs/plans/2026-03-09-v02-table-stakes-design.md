# Znap v0.2 — Table Stakes Design

**Date:** 2026-03-09
**Scope:** Tier 1 features — 6 features to reach competitive baseline
**Status:** Approved

---

## Feature 1: Per-Mode Global Hotkey Customization

**Problem:** Hotkeys are hardcoded. Power users need customizable shortcuts per capture mode.

**Design:**
- New `ShortcutRecorderView` — click a field, press any key combo, it captures keyCode + modifiers
- Uses `NSEvent.addLocalMonitorForEvents` to capture the key press
- Validates against reserved system shortcuts, rejects conflicts
- New **Shortcuts tab** in PreferencesView listing all 9 modes (All-In-One, Area, Fullscreen, Window, Freeze, OCR, Scroll, Record + future modes)
- Persist bindings in `UserDefaults` as dictionary (mode name → keyCode + modifiers), fallback to current defaults
- `AppDelegate` reads from prefs on launch and registers via `HotkeyService`
- When a shortcut is changed in preferences, unregister old and register new live

**Files:** `ShortcutRecorderView.swift` (new), `Preferences.swift`, `PreferencesView.swift`, `AppDelegate.swift`

---

## Feature 2: Hide Desktop Icons Before Capture

**Problem:** Messy desktops ruin screenshot aesthetics. CleanShot X's #1 loved feature.

**Design:**
- `DesktopIconManager` and `autoHideDesktopIcons` preference already exist
- Wire into `AppDelegate` capture flow: check pref → hide before capture → restore after completion or cancel
- Add toggle in PreferencesView under Capture section
- Add quick toggle in menu bar dropdown for fast access

**Files:** `AppDelegate.swift`, `PreferencesView.swift`, `ZnapApp.swift`

---

## Feature 3: GIF Export from Recordings

**Problem:** Users switching from Shottr want GIF support. GIFEncoder exists but isn't wired to UI.

**Design:**
- Add "Export as GIF" button in `VideoEditorPanel` alongside existing save
- Use `AVAssetImageGenerator` to extract frames from the edited composition at configurable rate (default 10fps)
- Respect trim/split/deleted segments from the video editor
- Feed frames to existing `GIFEncoder`
- Show progress indicator during encoding
- NSSavePanel with `.gif` type
- New `gifFrameRate` preference (5/10/15 fps) in PreferencesView under Recording section

**Files:** `VideoEditorPanel.swift`, `GIFEncoder.swift` (API adjustments), `Preferences.swift`, `PreferencesView.swift`

---

## Feature 4: Instant OCR Toast

**Problem:** Current OCR notification uses UNNotification which is slow and requires permissions. Need snappier feedback.

**Design:**
- Current OCR flow already works correctly: capture area → extract text → copy to clipboard
- Replace `showOCRNotification` (UNNotification) with lightweight transient toast HUD
- Toast: small rounded panel, centered on screen, shows "Copied!" or text preview, fades out after 1.5s
- ToastView is a reusable component for Features 4, 5, and 2

**Files:** `ToastView.swift` (new), `AppDelegate.swift`

---

## Feature 5: Destination Modifiers

**Problem:** Every capture goes through QAO. Power users want zero-friction shortcuts to save/copy directly.

**Design:**
- Detect `NSEvent.modifierFlags` at the moment of capture completion (mouse-up)
- No modifier → Quick Access Overlay (current behavior)
- Option held → save to default save location, show toast "Saved to Desktop"
- Control held → copy to clipboard, show toast "Copied!"
- Shift held → open annotation editor directly
- Modifier detection in selection overlay's completion handler, passed back to AppDelegate
- Applies to: area, fullscreen, window, freeze captures
- Excluded: scrolling capture (own flow), OCR (already copies to clipboard)
- Reuses ToastView from Feature 4

**Files:** `AppDelegate.swift`, `OverlayWindow.swift`/`SelectionView.swift` (pass modifiers), `WindowHighlightOverlay.swift`

---

## Feature 6: Window Shadow Toggle in UI

**Problem:** `includeWindowShadow` preference exists but isn't exposed in the UI.

**Design:**
- Add toggle in PreferencesView under Capture section: "Include window shadow"
- Add quick toggle in menu bar dropdown
- No capture pipeline changes — already respects the preference

**Files:** `PreferencesView.swift`, `ZnapApp.swift`

---

## Shared Infrastructure

### ToastView (new)
- Small NSPanel (non-activating, floating) with rounded corners and blur background
- Displays icon + message text
- Fades in, holds 1.5s, fades out
- Used by: OCR confirmation, destination modifier feedback, desktop icon hide confirmation

### ShortcutRecorderView (new)
- SwiftUI view wrapping NSEvent-based key combo capture
- Click to start recording → press key combo → displays human-readable shortcut
- Validates: rejects reserved combos, detects conflicts with other modes
- Clear button to reset to default
