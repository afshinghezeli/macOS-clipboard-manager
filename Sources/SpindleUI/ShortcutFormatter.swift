public import AppKit
import Carbon.HIToolbox
public import SpindleCore
import SpindleSystem

/// Shows shortcuts the way macOS menus do: ⌃⌘V, ⌥Space, ⇧⌘F5.
@MainActor
public enum ShortcutFormatter {
    public static func string(for shortcut: KeyboardShortcut) -> String {
        shortcut.modifiers.symbols + keyName(shortcut.keyCode)
    }

    static func keyName(_ keyCode: UInt16) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        return KeyboardLayout.character(forKeyCode: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// Keys whose layout character is invisible or unhelpful.
    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// The shortcut a key press describes, ignoring Caps Lock and the Fn and numeric-pad flags.
    public static func shortcut(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> KeyboardShortcut {
        var modifiers: KeyboardShortcut.Modifiers = []
        if modifierFlags.contains(.control) { modifiers.insert(.control) }
        if modifierFlags.contains(.option) { modifiers.insert(.option) }
        if modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if modifierFlags.contains(.command) { modifiers.insert(.command) }
        return KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
    }
}
