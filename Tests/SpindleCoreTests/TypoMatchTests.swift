import Testing

@testable import SpindleCore

@Suite
struct TypoMatchTests {
    private func edits(_ query: String, _ text: String) -> Int? {
        TypoMatch(query: query.split(separator: " ").map(String.init))?.edits(in: text)
    }

    @Test
    func exactWordsNeedNoEdits() {
        #expect(edits("clipboard", "the clipboard remembers") == 0)
    }

    @Test
    func oneTypoInAMediumWord() {
        #expect(edits("clipbord", "the clipboard remembers") == 1)  // missing letter
        #expect(edits("clipbaord", "the clipboard remembers") == 1)  // swapped letters
        #expect(edits("reciept", "your receipt for march") == 1)
        #expect(edits("recxipt", "your receipt for march") == 1)  // wrong letter
    }

    @Test
    func longWordsAllowTwoEdits() {
        #expect(edits("quartrely raprot", "quarterly report") == nil)  // "raprot" has 6 letters: one edit only
        #expect(edits("quartrely", "quarterly report") == 1)
        #expect(edits("qaurtrely", "quarterly report") == 2)
        #expect(edits("qxartrely", "quarterly report") == 2)
    }

    @Test
    func tooManyEditsIsNoMatch() {
        #expect(edits("clpbrd", "the clipboard remembers") == nil)
        #expect(edits("recipes", "your receipt for march") == nil)
    }

    @Test
    func anUnfinishedWordMatchesTheStartOfOne() {
        #expect(edits("clipbao", "the clipboard remembers") == 1)
        #expect(edits("rememb", "the clipboard remembers") == 0)
        #expect(edits("remembr", "the clipboard remembers") == 1)
    }

    @Test
    func shortWordsMustAppearAsTyped() {
        #expect(edits("git staus", "git status --short") == 1)
        #expect(edits("gti status", "git status --short") == nil)
        #expect(edits("-- staus", "git status --short") == 1)
    }

    @Test
    func everyWordMustMatchAndEditsAddUp() {
        #expect(edits("clipbaord remembres", "the clipboard remembers") == 2)
        #expect(edits("clipbaord forgets", "the clipboard remembers") == nil)
    }

    @Test
    func queriesWithoutAWordLongEnoughToCorrectGiveNoMatcher() {
        #expect(TypoMatch(query: ["ab", "cd"]) == nil)
        #expect(TypoMatch(query: []) == nil)
    }

    @Test
    func worksOnAnyScript() {
        #expect(edits("brulee", "creme brulee") == 0)
        #expect(edits("カレンダ", "カレンダー") == 0)
        #expect(edits("カレソダー", "カレンダー") == 1)
    }
}
