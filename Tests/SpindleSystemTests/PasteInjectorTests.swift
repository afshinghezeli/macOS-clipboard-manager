import CoreGraphics
import Testing

@testable import SpindleSystem

// Posting events can't be tested here: it needs a permission, and it would paste into whatever app
// is in front. These check the parts that decide what gets posted.
@MainActor
@Suite
struct PasteInjectorTests {
    @Test
    func commandCarriesTheLeftCommandKeyBit() {
        #expect(PasteInjector.commandFlags.contains(.maskCommand))
        #expect(PasteInjector.commandFlags.rawValue & 0x8 == 0x8)
    }

    @Test
    func pasteKeyTypesVOnThisMac() {
        let code = PasteInjector.pasteKeyCode()
        #expect(KeyboardLayout.character(forKeyCode: code) == "v" || code == 9)
    }
}
