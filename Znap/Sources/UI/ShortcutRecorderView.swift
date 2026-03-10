import SwiftUI
import Carbon

/// A row that displays a capture mode label and a button to record a new shortcut.
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
            .frame(width: 140)
            .background(
                ShortcutRecorderNSView(isRecording: $isRecording, binding: $binding)
                    .frame(width: 0, height: 0)
            )
        }
    }
}

/// An invisible NSView bridge that installs a local key monitor to capture
/// the next keypress when recording is active.
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

    final class Coordinator {
        var isRecording = false {
            didSet {
                if isRecording { startMonitoring() }
                else { stopMonitoring() }
            }
        }
        private var isRecordingBinding: Binding<Bool>
        private var bindingBinding: Binding<HotkeyBinding>
        private var monitor: Any?

        init(isRecording: Binding<Bool>, binding: Binding<HotkeyBinding>) {
            self.isRecordingBinding = isRecording
            self.bindingBinding = binding
        }

        func startMonitoring() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isRecording else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                // Escape cancels recording
                if event.keyCode == UInt16(kVK_Escape) {
                    self.isRecordingBinding.wrappedValue = false
                    return nil
                }

                // Require at least Cmd or Ctrl modifier
                guard flags.contains(.command) || flags.contains(.control) else { return event }

                var carbonMods: UInt32 = 0
                if flags.contains(.command) { carbonMods |= UInt32(Carbon.cmdKey) }
                if flags.contains(.shift)   { carbonMods |= UInt32(Carbon.shiftKey) }
                if flags.contains(.option)  { carbonMods |= UInt32(Carbon.optionKey) }
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
