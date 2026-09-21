public import AppKit

/// Something the user can do in the panel from the keyboard.
public enum PanelCommand: Hashable, Sendable {
    case moveUp, moveDown, pageUp, pageDown
    /// Paste into the app that was in front (↵).
    case paste
    /// Paste only the plain text (⇧↵).
    case pasteAsPlainText
    /// Put it on the clipboard without pasting (⌘↵).
    case copy
    /// Paste the item shown at this position, 0-based (⌘1…⌘9).
    case quickPaste(Int)
    /// Clear the search, or close the panel when there's nothing to clear (Esc).
    case escape
    case showActions
    case togglePin
    case movePinUp
    case movePinDown
    case delete
    case nextFilter
}

/// Which ⌘ shortcuts mean which command. Follows Raycast where it has one, so people switching
/// keep their habits (see `.claude/rules/ui.md`).
public enum PanelKeyMap {
    public static func command(forKeyEquivalent characters: String, modifiers: NSEvent.ModifierFlags) -> PanelCommand? {
        let modifiers = modifiers.intersection([.command, .shift, .option, .control])
        if modifiers == [.command, .option] {
            switch characters {
            case String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!): return .movePinUp
            case String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!): return .movePinDown
            default: return nil
            }
        }
        guard modifiers == .command else { return nil }
        switch characters {
        case "\r": return .copy
        case "k": return .showActions
        case ".": return .togglePin
        case "p": return .nextFilter
        case "\u{7F}", "\u{8}": return .delete  // ⌘⌫
        default:
            if let digit = Int(characters), (1...9).contains(digit) { return .quickPaste(digit - 1) }
            return nil
        }
    }
}
