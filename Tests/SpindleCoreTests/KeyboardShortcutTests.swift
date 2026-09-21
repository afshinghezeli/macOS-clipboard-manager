import Foundation
import Testing

@testable import SpindleCore

@Suite
struct KeyboardShortcutTests {
    @Test
    func theDefaultIsControlCommandV() {
        #expect(KeyboardShortcut.openPanelDefault.keyCode == 9)
        #expect(KeyboardShortcut.openPanelDefault.modifiers.symbols == "⌃⌘")
    }

    @Test
    func modifiersReadInMenuOrder() {
        let all: KeyboardShortcut.Modifiers = [.command, .shift, .option, .control]
        #expect(all.symbols == "⌃⌥⇧⌘")
    }

    @Test
    func globalShortcutsNeedCommandOrControl() {
        #expect(KeyboardShortcut(keyCode: 9, modifiers: [.command]).isValidGlobalShortcut)
        #expect(KeyboardShortcut(keyCode: 9, modifiers: [.control]).isValidGlobalShortcut)
        #expect(!KeyboardShortcut(keyCode: 9, modifiers: [.option]).isValidGlobalShortcut)
        #expect(!KeyboardShortcut(keyCode: 9, modifiers: [.option, .shift]).isValidGlobalShortcut)
    }

    @Test
    func survivesARoundTripThroughJSON() throws {
        let shortcut = KeyboardShortcut(keyCode: 49, modifiers: [.option, .command])
        let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: JSONEncoder().encode(shortcut))
        #expect(decoded == shortcut)
    }
}
