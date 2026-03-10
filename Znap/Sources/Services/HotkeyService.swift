import Carbon
import Cocoa

/// Service that manages global keyboard shortcuts using Carbon's RegisterEventHotKey API.
///
/// Usage:
/// ```
/// let id = HotkeyService.shared.register(
///     keyCode: UInt32(kVK_ANSI_4),
///     modifiers: UInt32(Carbon.cmdKey) | UInt32(Carbon.shiftKey),
///     handler: { print("Hotkey pressed!") }
/// )
/// ```
final class HotkeyService {
    static let shared = HotkeyService()

    /// Represents a registered global hotkey.
    struct Hotkey {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let handler: () -> Void
    }

    /// The signature used for EventHotKeyID, ASCII for "ZNAP".
    private static let hotkeySignature: UInt32 = 0x5A4E4150

    /// Auto-incrementing counter for hotkey IDs.
    private var nextID: UInt32 = 1

    /// Dictionary mapping hotkey IDs to their Hotkey structs.
    private(set) var hotkeys: [UInt32: Hotkey] = [:]

    /// Dictionary mapping hotkey IDs to their Carbon EventHotKeyRef for unregistration.
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]

    /// Reference to the installed Carbon event handler.
    private var eventHandlerRef: EventHandlerRef?

    private init() {
        installEventHandler()
    }

    // MARK: - Public API

    /// Registers a global hotkey.
    ///
    /// - Parameters:
    ///   - keyCode: The virtual key code (e.g. `UInt32(kVK_ANSI_4)`).
    ///   - modifiers: Carbon modifier flags (e.g. `UInt32(Carbon.cmdKey) | UInt32(Carbon.shiftKey)`).
    ///   - handler: Closure invoked on the main thread when the hotkey is pressed.
    /// - Returns: A unique hotkey ID that can be used to unregister later.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1

        let hotkey = Hotkey(id: id, keyCode: keyCode, modifiers: modifiers, handler: handler)
        hotkeys[id] = hotkey

        // Build the EventHotKeyID with our signature and the unique ID.
        let hotkeyID = EventHotKeyID(signature: HotkeyService.hotkeySignature, id: id)
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status != noErr {
            NSLog("HotkeyService: Failed to register hotkey (id=\(id), status=\(status))")
        } else if let hotkeyRef {
            hotkeyRefs[id] = hotkeyRef
        }

        return id
    }

    /// Unregisters all currently registered hotkeys.
    func unregisterAll() {
        for (id, ref) in hotkeyRefs {
            let status = UnregisterEventHotKey(ref)
            if status != noErr {
                NSLog("HotkeyService: Failed to unregister hotkey (id=\(id), status=\(status))")
            }
        }
        hotkeys.removeAll()
        hotkeyRefs.removeAll()
    }

    // MARK: - Carbon Event Handler

    /// Installs the Carbon event handler that listens for hotkey press events.
    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Pass `self` as userData so the C callback can route events back to us.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        if status != noErr {
            NSLog("HotkeyService: Failed to install event handler (status=\(status))")
        }
    }
}

/// C-compatible callback function for Carbon hotkey events.
///
/// This is defined at file scope because Carbon requires a C function pointer,
/// which cannot capture context. The `userData` parameter carries the
/// `HotkeyService` instance pointer.
private func hotkeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event, let userData = userData else {
        return OSStatus(eventNotHandledErr)
    }

    // Recover the HotkeyService instance from the userData pointer.
    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()

    // Extract the EventHotKeyID from the event.
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )

    guard status == noErr else {
        return status
    }

    // Look up the handler for this hotkey ID and dispatch it on the main queue.
    if let hotkey = service.hotkeys[hotkeyID.id] {
        DispatchQueue.main.async {
            hotkey.handler()
        }
    }

    return noErr
}
