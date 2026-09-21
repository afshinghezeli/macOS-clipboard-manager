public import AppKit
import Carbon.HIToolbox

/// Pastes into another app by posting ⌘V, as if the user pressed it.
///
/// Needs the PostEvent privilege (listed under System Settings → Privacy & Security →
/// Accessibility), not full Accessibility; it works inside the App Sandbox.
@MainActor
public enum PasteInjector {
    public enum Failure: Error, Equatable {
        case notPermitted
        case targetNotFrontmost
    }

    /// Whether macOS currently lets Spindle post key events.
    public static var isPermitted: Bool { CGPreflightPostEventAccess() }

    /// Shows macOS's permission prompt, if it hasn't been answered yet. Returns whether posting is
    /// allowed now. Call only in response to something the user did.
    @discardableResult
    public static func requestPermission() -> Bool {
        CGRequestPostEventAccess()
    }

    /// Makes sure `target` is in front, waits until the user has let go of the modifier keys,
    /// then posts ⌘V.
    public static func paste(into target: NSRunningApplication?) async throws(Failure) {
        guard isPermitted else { throw .notPermitted }

        if let target, NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            target.activate(from: .current, options: [])
            if !(await waitUntil(timeout: .milliseconds(500)) {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
            }) {
                throw .targetNotFrontmost
            }
        }
        // Still holding ⌥ when ⌘V arrives turns Finder's paste into "Move Item Here".
        _ = await waitUntil(timeout: .milliseconds(600)) {
            CGEventSource.flagsState(.hidSystemState).intersection([
                .maskCommand, .maskAlternate, .maskShift, .maskControl,
            ])
            .isEmpty
        }
        // Give the target's key window a moment to take focus back from the panel.
        try? await Task.sleep(for: .milliseconds(40))

        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        let keyCode = CGKeyCode(pasteKeyCode())
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = commandFlags
        up?.flags = commandFlags
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    /// ⌘ plus the left-⌘ device bit; some apps ignore a ⌘ that doesn't say which key it came from.
    static let commandFlags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | UInt64(NX_DEVICELCMDKEYMASK))

    /// The key that types "v" in the layout shortcuts use. Layouts whose name ends in "⌘" (such as
    /// "Dvorak – QWERTY ⌘") switch to QWERTY while ⌘ is held, so they get the QWERTY V.
    static func pasteKeyCode() -> UInt16 {
        let qwertyV = UInt16(kVK_ANSI_V)
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let raw = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
        {
            let name = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
            if name.hasSuffix("⌘") { return qwertyV }
        }
        return KeyboardLayout.keyCode(forCharacter: "v") ?? qwertyV
    }

    private static func waitUntil(timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }
}
