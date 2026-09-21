public import AppKit
import SpindleCore
public import SpindleStorage

/// One entry of the ⌘K actions menu.
public struct PanelAction: Hashable {
    public var title: String
    public var keyEquivalent: String
    public var modifiers: NSEvent.ModifierFlags
    public var command: PanelCommand

    public static func == (lhs: PanelAction, rhs: PanelAction) -> Bool {
        lhs.title == rhs.title && lhs.command == rhs.command
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(command)
    }
}

/// Which actions apply to an item, in menu order, each with the shortcut that also works without
/// the menu. The menu is where people discover the shortcuts.
public enum PanelActions {
    public static func list(for item: ItemSummary, targetAppName: String?, canPaste: Bool) -> [PanelAction] {
        var actions: [PanelAction] = []
        if canPaste, let targetAppName {
            actions.append(
                PanelAction(
                    title: String(
                        localized: "Paste to \(targetAppName)", bundle: .spindleUI,
                        comment: "Footer: the Return key pastes into this app."),
                    keyEquivalent: "\r", modifiers: [], command: .paste))
            if item.kind != .image && item.kind != .file {
                actions.append(
                    PanelAction(
                        title: String(
                            localized: "Paste as Plain Text", bundle: .spindleUI,
                            comment: "Action: paste without formatting."),
                        keyEquivalent: "\r", modifiers: .shift, command: .pasteAsPlainText))
            }
        }
        actions.append(
            PanelAction(
                title: String(
                    localized: "Copy to Clipboard", bundle: .spindleUI,
                    comment: "Footer: the Return key copies the item."),
                keyEquivalent: "\r", modifiers: .command, command: .copy))
        actions.append(
            PanelAction(
                title: item.isPinned
                    ? String(localized: "Unpin", bundle: .spindleUI, comment: "Action: remove from the pinned items.")
                    : String(localized: "Pin", bundle: .spindleUI, comment: "Action: keep at the top, never removed."),
                keyEquivalent: ".", modifiers: .command, command: .togglePin))
        if item.isPinned {
            actions.append(
                PanelAction(
                    title: String(localized: "Move Up", bundle: .spindleUI, comment: "Action: move a pinned item up."),
                    keyEquivalent: String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!),
                    modifiers: [.command, .option],
                    command: .movePinUp))
            actions.append(
                PanelAction(
                    title: String(
                        localized: "Move Down", bundle: .spindleUI, comment: "Action: move a pinned item down."),
                    keyEquivalent: String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!),
                    modifiers: [.command, .option],
                    command: .movePinDown))
        }
        actions.append(
            PanelAction(
                title: String(
                    localized: "Delete", bundle: .spindleUI, comment: "Action: remove the item from the history."),
                keyEquivalent: String(UnicodeScalar(UInt8(NSBackspaceCharacter))), modifiers: .command, command: .delete
            ))
        return actions
    }
}
