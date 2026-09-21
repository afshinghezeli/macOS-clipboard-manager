import SpindleCore
import Testing

@testable import SpindleSystem

@MainActor
@Suite
struct HotKeyCenterTests {
    // ⌃⌥⇧⌘F19: nobody has that one, so the tests never collide with the Mac's real shortcuts.
    private let unusual = KeyboardShortcut(keyCode: 80, modifiers: [.control, .option, .shift, .command])

    @Test
    func registersAndUnregisters() throws {
        let center = HotKeyCenter.shared
        let id = try center.register(unusual) {}
        center.unregister(id)
        // Free again, so registering once more works.
        let again = try center.register(unusual) {}
        center.unregister(again)
    }

    @Test
    func reportsACombinationThatIsAlreadyTaken() throws {
        let center = HotKeyCenter.shared
        let id = try center.register(unusual) {}
        defer { center.unregister(id) }
        #expect(throws: HotKeyCenter.RegistrationError.taken) { try center.register(unusual) {} }
    }

    @Test
    func mapsModifiersToCarbon() {
        #expect(HotKeyCenter.carbonModifiers([.command]) == 256)
        #expect(HotKeyCenter.carbonModifiers([.control, .command]) == 256 | 4096)
        #expect(HotKeyCenter.carbonModifiers([.option, .shift]) == 2048 | 512)
    }
}
