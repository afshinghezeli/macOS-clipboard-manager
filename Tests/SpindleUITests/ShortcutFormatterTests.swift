import AppKit
import SpindleCore
import Testing

@testable import SpindleUI

@MainActor
@Suite
struct ShortcutFormatterTests {
    @Test
    func showsModifiersInMenuOrderThenTheKey() {
        #expect(ShortcutFormatter.string(for: KeyboardShortcut(keyCode: 49, modifiers: [.option])) == "⌥Space")
        #expect(ShortcutFormatter.string(for: KeyboardShortcut(keyCode: 96, modifiers: [.shift, .command])) == "⇧⌘F5")
        #expect(ShortcutFormatter.string(for: KeyboardShortcut(keyCode: 126, modifiers: [.control])) == "⌃↑")
    }

    @Test
    func readsKeyPressesWithoutCapsLockOrFn() {
        let shortcut = ShortcutFormatter.shortcut(
            keyCode: 9, modifierFlags: [.control, .command, .capsLock, .function])
        #expect(shortcut == KeyboardShortcut(keyCode: 9, modifiers: [.control, .command]))
    }
}
