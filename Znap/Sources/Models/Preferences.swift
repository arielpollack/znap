import SwiftUI
import Carbon

// MARK: - Hotkey Binding

/// Represents a persisted keyboard shortcut binding.
struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon modifier flags

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(Carbon.controlKey) != 0 { parts.append("\u{2303}") }
        if modifiers & UInt32(Carbon.optionKey) != 0 { parts.append("\u{2325}") }
        if modifiers & UInt32(Carbon.shiftKey) != 0 { parts.append("\u{21e7}") }
        if modifiers & UInt32(Carbon.cmdKey) != 0 { parts.append("\u{2318}") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }
}

/// Converts a Carbon virtual key code to a human-readable string.
func keyCodeToString(_ keyCode: UInt32) -> String {
    switch Int(keyCode) {
    // Letters
    case kVK_ANSI_A: return "A"
    case kVK_ANSI_B: return "B"
    case kVK_ANSI_C: return "C"
    case kVK_ANSI_D: return "D"
    case kVK_ANSI_E: return "E"
    case kVK_ANSI_F: return "F"
    case kVK_ANSI_G: return "G"
    case kVK_ANSI_H: return "H"
    case kVK_ANSI_I: return "I"
    case kVK_ANSI_J: return "J"
    case kVK_ANSI_K: return "K"
    case kVK_ANSI_L: return "L"
    case kVK_ANSI_M: return "M"
    case kVK_ANSI_N: return "N"
    case kVK_ANSI_O: return "O"
    case kVK_ANSI_P: return "P"
    case kVK_ANSI_Q: return "Q"
    case kVK_ANSI_R: return "R"
    case kVK_ANSI_S: return "S"
    case kVK_ANSI_T: return "T"
    case kVK_ANSI_U: return "U"
    case kVK_ANSI_V: return "V"
    case kVK_ANSI_W: return "W"
    case kVK_ANSI_X: return "X"
    case kVK_ANSI_Y: return "Y"
    case kVK_ANSI_Z: return "Z"
    // Numbers
    case kVK_ANSI_0: return "0"
    case kVK_ANSI_1: return "1"
    case kVK_ANSI_2: return "2"
    case kVK_ANSI_3: return "3"
    case kVK_ANSI_4: return "4"
    case kVK_ANSI_5: return "5"
    case kVK_ANSI_6: return "6"
    case kVK_ANSI_7: return "7"
    case kVK_ANSI_8: return "8"
    case kVK_ANSI_9: return "9"
    // Special keys
    case kVK_Space: return "Space"
    case kVK_Return: return "Return"
    case kVK_Tab: return "Tab"
    case kVK_Delete: return "Delete"
    case kVK_ForwardDelete: return "Fwd Del"
    case kVK_Escape: return "Esc"
    // Arrow keys
    case kVK_LeftArrow: return "\u{2190}"
    case kVK_RightArrow: return "\u{2192}"
    case kVK_UpArrow: return "\u{2191}"
    case kVK_DownArrow: return "\u{2193}"
    // Function keys
    case kVK_F1: return "F1"
    case kVK_F2: return "F2"
    case kVK_F3: return "F3"
    case kVK_F4: return "F4"
    case kVK_F5: return "F5"
    case kVK_F6: return "F6"
    case kVK_F7: return "F7"
    case kVK_F8: return "F8"
    case kVK_F9: return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    // Punctuation
    case kVK_ANSI_Minus: return "-"
    case kVK_ANSI_Equal: return "="
    case kVK_ANSI_LeftBracket: return "["
    case kVK_ANSI_RightBracket: return "]"
    case kVK_ANSI_Backslash: return "\\"
    case kVK_ANSI_Semicolon: return ";"
    case kVK_ANSI_Quote: return "'"
    case kVK_ANSI_Comma: return ","
    case kVK_ANSI_Period: return "."
    case kVK_ANSI_Slash: return "/"
    case kVK_ANSI_Grave: return "`"
    default: return "Key\(keyCode)"
    }
}

// MARK: - Capture Mode

/// Identifies each capture/recording mode for hotkey binding.
enum CaptureMode: String, CaseIterable {
    case allInOne, area, fullscreen, window, freeze, ocr, scroll, record

    var label: String {
        switch self {
        case .allInOne:   return "All-In-One"
        case .area:       return "Capture Area"
        case .fullscreen: return "Capture Fullscreen"
        case .window:     return "Capture Window"
        case .freeze:     return "Freeze & Capture"
        case .ocr:        return "OCR Text"
        case .scroll:     return "Scrolling Capture"
        case .record:     return "Record Screen"
        }
    }

    var defaultBinding: HotkeyBinding {
        switch self {
        case .allInOne:   return HotkeyBinding(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .area:       return HotkeyBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .fullscreen: return HotkeyBinding(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .window:     return HotkeyBinding(keyCode: UInt32(kVK_ANSI_8), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .freeze:     return HotkeyBinding(keyCode: UInt32(kVK_ANSI_6), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .ocr:        return HotkeyBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .scroll:     return HotkeyBinding(keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        case .record:     return HotkeyBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(Carbon.cmdKey | Carbon.shiftKey))
        }
    }
}

/// Observable object that persists user preferences using `@AppStorage`.
///
/// ``ZnapPreferences`` centralises all user-configurable settings so that
/// they can be read from any SwiftUI view or service. Values are automatically
/// saved to `UserDefaults`.
final class ZnapPreferences: ObservableObject {

    // MARK: - General

    /// Default directory for saved screenshots.
    @AppStorage("defaultSaveLocation") var defaultSaveLocation = "~/Desktop"

    /// Whether to launch Znap automatically at login.
    @AppStorage("launchAtLogin") var launchAtLogin = false

    /// Number of days to keep capture history before automatic cleanup.
    @AppStorage("historyRetentionDays") var historyRetentionDays = 30

    // MARK: - Capture

    /// Default image format for saved screenshots.
    @AppStorage("defaultFormat") var defaultFormat = "png"

    /// JPEG compression quality (0.0–1.0), used when `defaultFormat` is `"jpeg"`.
    @AppStorage("jpegQuality") var jpegQuality = 0.85

    /// Auto-dismiss timeout for the Quick Access Overlay, in seconds.
    @AppStorage("qaoAutoDismiss") var qaoAutoDismiss = 15.0

    /// Whether to include the native macOS window shadow in window captures.
    @AppStorage("includeWindowShadow") var includeWindowShadow = true

    /// Whether to automatically hide desktop icons before each capture.
    @AppStorage("autoHideDesktopIcons") var autoHideDesktopIcons = false

    /// Whether to open the annotation editor immediately after capture
    /// instead of showing the Quick Access Overlay thumbnail.
    @AppStorage("autoOpenEditor") var autoOpenEditor = false

    // MARK: - Recording

    /// Frames per second for screen recordings.
    @AppStorage("recordingFPS") var recordingFPS = 30

    /// Output format for screen recordings.
    @AppStorage("recordingFormat") var recordingFormat = "mp4"

    /// Frames per second for GIF exports from the video editor.
    @AppStorage("gifFrameRate") var gifFrameRate = 10

    // MARK: - Hotkey Bindings

    /// Returns the stored hotkey binding for a capture mode, or its default.
    func binding(for mode: CaptureMode) -> HotkeyBinding {
        let key = "hotkey_\(mode.rawValue)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data)
        else { return mode.defaultBinding }
        return binding
    }

    /// Persists a hotkey binding for a capture mode.
    func setBinding(_ binding: HotkeyBinding, for mode: CaptureMode) {
        let key = "hotkey_\(mode.rawValue)"
        if let data = try? JSONEncoder().encode(binding) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
