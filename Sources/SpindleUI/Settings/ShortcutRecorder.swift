import AppKit
import SpindleCore
import SpindleSystem
import SwiftUI

/// Shows a shortcut and records a new one: click, then press the keys. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var shortcut: SpindleCore.KeyboardShortcut
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(action: toggleRecording) {
                    Text(verbatim: isRecording ? recordingPrompt : ShortcutFormatter.string(for: shortcut))
                        .frame(minWidth: 120)
                }
                if shortcut != .openPanelDefault && !isRecording {
                    Button(String(localized: "Use Default", bundle: .spindleUI, comment: "Resets the shortcut to ⌃⌘V."))
                    {
                        shortcut = .openPanelDefault
                        problem = nil
                    }
                }
            }
            if let problem {
                Text(verbatim: problem).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var recordingPrompt: String {
        String(localized: "Type the shortcut…", bundle: .spindleUI, comment: "Shortcut recorder while recording.")
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        problem = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event)
            return nil  // the key press only sets the shortcut
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func record(_ event: NSEvent) {
        let candidate = ShortcutFormatter.shortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        if candidate.modifiers.isEmpty && event.keyCode == 53 {  // Esc
            stopRecording()
            return
        }
        guard candidate.isValidGlobalShortcut else {
            problem = String(
                localized: "Include ⌘ or ⌃, so the shortcut doesn't type a character.", bundle: .spindleUI,
                comment: "Shortcut recorder: the combination has no Command or Control key.")
            return
        }
        guard candidate == shortcut || HotKeyCenter.shared.isAvailable(candidate) else {
            problem = String(
                localized: "Another app already uses \(ShortcutFormatter.string(for: candidate)).", bundle: .spindleUI,
                comment: "Shortcut recorder: the combination belongs to another app.")
            return
        }
        problem = nil
        shortcut = candidate
        stopRecording()
    }
}
