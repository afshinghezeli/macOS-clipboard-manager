import AppKit
import Testing

@testable import SpindleUI

@Suite
struct PanelKeyMapTests {
    @Test(arguments: [
        ("\r", PanelCommand.copy), ("k", .showActions), (".", .togglePin), ("p", .nextFilter), ("\u{7F}", .delete),
        ("1", .quickPaste(0)), ("9", .quickPaste(8)),
    ])
    func commandShortcuts(_ characters: String, _ expected: PanelCommand) {
        #expect(PanelKeyMap.command(forKeyEquivalent: characters, modifiers: .command) == expected)
    }

    @Test
    func otherModifierCombinationsAreLeftAlone() {
        #expect(PanelKeyMap.command(forKeyEquivalent: "k", modifiers: [.command, .shift]) == nil)
        #expect(PanelKeyMap.command(forKeyEquivalent: "k", modifiers: []) == nil)
        #expect(PanelKeyMap.command(forKeyEquivalent: "0", modifiers: .command) == nil)
        // ⌘C, ⌘V, ⌘A belong to the search field (Edit menu).
        #expect(PanelKeyMap.command(forKeyEquivalent: "c", modifiers: .command) == nil)
    }

    @Test
    func capsLockDoesNotGetInTheWay() {
        #expect(PanelKeyMap.command(forKeyEquivalent: "k", modifiers: [.command, .capsLock]) == .showActions)
    }

    @Test
    func optionCommandArrowsReorderPins() {
        let up = String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!)
        let down = String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)
        #expect(PanelKeyMap.command(forKeyEquivalent: up, modifiers: [.command, .option]) == .movePinUp)
        #expect(PanelKeyMap.command(forKeyEquivalent: down, modifiers: [.command, .option]) == .movePinDown)
        #expect(PanelKeyMap.command(forKeyEquivalent: up, modifiers: [.command]) == nil)
    }
}
