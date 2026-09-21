import Carbon.HIToolbox

/// Translates between physical key positions and the characters the current keyboard layout puts
/// on them. Must be called on the main thread (Text Input Sources isn't thread-safe).
@MainActor
public enum KeyboardLayout {
    /// The character the key types, lowercased, using the ASCII-capable layout that macOS uses for
    /// shortcuts. For showing shortcuts, e.g. "v" for key code 9 on QWERTY and "." on Dvorak.
    public static func character(forKeyCode keyCode: UInt16) -> String? {
        guard let layout = asciiCapableLayoutData() else { return nil }
        return translate(keyCode, in: layout)
    }

    /// The key that types `character`: first in the current layout, then in the ASCII-capable one
    /// macOS falls back to for shortcuts (Russian, Greek, Hebrew…). Apps match ⌘V by character, so
    /// pasting on Dvorak or AZERTY must press the key that types "v" there, not the QWERTY V.
    public static func keyCode(forCharacter character: String) -> UInt16? {
        let target = character.lowercased()
        for layout in [currentLayoutData(), asciiCapableLayoutData()].compactMap({ $0 }) {
            for code in UInt16(0)..<128 where translate(code, in: layout) == target {
                return code
            }
        }
        return nil
    }

    // MARK: - Text Input Sources

    private static func currentLayoutData() -> Data? {
        TISCopyCurrentKeyboardLayoutInputSource().flatMap { layoutData($0.takeRetainedValue()) }
    }

    private static func asciiCapableLayoutData() -> Data? {
        TISCopyCurrentASCIICapableKeyboardLayoutInputSource().flatMap { layoutData($0.takeRetainedValue()) }
    }

    private static func layoutData(_ source: TISInputSource) -> Data? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    }

    private static func translate(_ keyCode: UInt16, in layoutData: Data) -> String? {
        layoutData.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length).lowercased()
        }
    }
}
