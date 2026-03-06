# Screen Recording UX Improvements

## Problem

Screen recording has no visual indication that capture is active, no accessible stop button, and no way to edit the recorded video before saving.

## Design

### 1. Recording Indicator — Floating Pill

A new `RecordingIndicatorPanel` (NSPanel) appears when recording starts.

**Appearance**: Small floating capsule (~200x36) with rounded corners and dark translucent background (NSVisualEffectView). Contains:
- Red pulsing dot (animated)
- Elapsed time label (e.g. `0:42`)
- Pause/Resume button (icon)
- Stop button (square icon, prominent)

**Position**: Top-center of the recorded display, offset 12px from top. Draggable.

**Behavior**:
- Fades in when recording starts
- Stays on top of all windows (floating level)
- Excluded from the recording via SCStream window exclusion
- Stop triggers `stopRecording()` and opens the video editor
- Pause toggles existing `togglePause()` functionality

**File**: `Znap/Sources/UI/RecordingIndicatorPanel.swift`

### 2. Video Editor Window

A `VideoEditorPanel` (NSPanel) opens after recording stops, replacing the Quick Access Overlay flow for recordings.

**Window** (~720x480, resizable):
- Video player (AVPlayer + AVPlayerLayer)
- Play/pause, current time / total duration
- Visual timeline with filmstrip thumbnails
- Split markers, trim handles, segment speed controls
- Cancel and Save buttons

**Timeline** (custom `VideoTimelineView`):
- Filmstrip thumbnail track generated via AVAssetImageGenerator
- Playhead (vertical red line) synced to playback
- Click timeline to add split markers (vertical yellow lines)
- Segments between markers are visually distinct blocks
- Drag start/end edges to trim
- Each segment shows speed label (default "1x")

**Segment controls**: Click a segment to get:
- Speed picker: 0.5x, 1x, 1.5x, 2x, 4x
- Delete segment button (dims/hatches the segment)

**Additional controls**:
- "Add Split" button (splits at current playhead)
- Undo (Cmd+Z) to remove last split or restore deleted segment

**Files**:
- `Znap/Sources/UI/VideoEditorPanel.swift`
- `Znap/Sources/UI/VideoTimelineView.swift`

### 3. Video Export

**Export process** (Save button):
- Uses `AVMutableComposition` to remove deleted segments, apply speed changes via `scaleTimeRange`, and trim start/end
- Exports via `AVAssetExportSession` with H.264 preset
- Saves to Desktop as `Znap-yyyy-MM-dd-HHmmss.mp4`
- Adds to `HistoryService`

**File**: `Znap/Sources/Services/VideoExportService.swift`

### 4. Integration

**Recording start** (AppDelegate `toggleRecording()`):
- After `startRecording()` succeeds, show `RecordingIndicatorPanel`
- Pass indicator's window ID to SCStream's excluded windows

**Recording stop**:
- Dismiss indicator pill, open `VideoEditorPanel` with recorded video URL
- QuickAccessOverlay no longer used for recordings (still used for screenshots)

**Files changed**:
- `AppDelegate.swift` — refactor `toggleRecording()` for pill + editor flow
- `RecordingService.swift` — add window exclusion support

**New files**:
- `UI/RecordingIndicatorPanel.swift`
- `UI/VideoEditorPanel.swift`
- `UI/VideoTimelineView.swift`
- `Services/VideoExportService.swift`

## Export Format

MP4 only (H.264).
