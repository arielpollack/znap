# Background Toggle in Annotation Editor

## Overview

Add a background toggle to the annotation toolbar that wraps screenshots in a styled background with padding, rounded corners, and shadow. Settings are configurable via a popover and persist across app restarts.

## Design

### Toolbar Button
- Background toggle button in `AnnotationToolbar` (SF Symbol: `rectangle.inset.filled`)
- Toggling ON opens a settings popover and enables background in preview/export
- Background state and config persist via UserDefaults as a single Codable object

### Settings Popover
- Reuses controls from existing `BackgroundToolView`: gradient presets, padding slider, corner radius slider, shadow toggle, aspect ratio picker
- Changes apply live (no "Apply" button)
- Popover dismisses on click-outside; background stays enabled

### Persistence
- Make `BackgroundRenderer.Config` (and its nested enums) `Codable`
- Store as single JSON blob in UserDefaults under key `backgroundConfig`
- Includes `enabled` flag in the config

### Live Preview
- `AnnotationCanvasView` renders background behind screenshot in real-time when enabled
- Canvas expands to accommodate padding; annotations draw on screenshot area

### Export
- `renderFinalImage()` wraps output with `BackgroundRenderer.render()` when enabled
