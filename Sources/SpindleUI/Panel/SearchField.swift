import AppKit
import SwiftUI

/// The panel's search field. An `NSTextField`, so the text system's own key bindings do the
/// routing: ↑/↓ and ⌃P/⌃N arrive as moveUp:/moveDown:, Return as insertNewline:, Esc as
/// cancelOperation:. That keeps editing keys (⌥←, ⌘⌫, ⌘A) working normally in the field.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Changes whenever the field should take keyboard focus.
    var focusToken: Int
    var onCommand: (PanelCommand) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20)
        field.placeholderString = placeholder
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.setAccessibilityLabel(placeholder)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            // After this layout pass, when the field is in its window.
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var focusToken: Int?

        init(parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let modifiers = NSApp.currentEvent?.modifierFlags.intersection([.shift, .command, .option, .control]) ?? []
            let command: PanelCommand? =
                switch selector {
                case #selector(NSResponder.moveUp(_:)): .moveUp
                case #selector(NSResponder.moveDown(_:)): .moveDown
                case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)): .pageUp
                case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)): .pageDown
                case #selector(NSResponder.insertNewline(_:)): modifiers.contains(.shift) ? .pasteAsPlainText : .paste
                case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)): .paste
                case #selector(NSResponder.cancelOperation(_:)): .escape
                default: nil
                }
            guard let command else { return false }
            return parent.onCommand(command)
        }
    }
}
