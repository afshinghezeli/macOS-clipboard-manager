import Testing

@testable import SpindleSystem

@MainActor
@Suite
struct KeyboardLayoutTests {
    // The layout depends on the Mac running the tests, so these check consistency, not QWERTY.
    @Test
    func translatesBothWays() throws {
        let code = try #require(KeyboardLayout.keyCode(forCharacter: "v"))
        #expect(KeyboardLayout.character(forKeyCode: code) == "v")
    }

    @Test
    func findsUppercaseCharactersToo() {
        #expect(KeyboardLayout.keyCode(forCharacter: "V") == KeyboardLayout.keyCode(forCharacter: "v"))
    }

    @Test
    func unknownCharactersHaveNoKey() {
        #expect(KeyboardLayout.keyCode(forCharacter: "🙂") == nil)
    }
}
