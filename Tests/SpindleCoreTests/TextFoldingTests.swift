import Foundation
import Testing

@testable import SpindleCore

@Suite
struct TextFoldingTests {
    @Test(arguments: [
        ("Crème Brûlée", "creme brulee"),
        ("STRASSE", "strasse"),
        ("Ｓｐｉｎｄｌｅ", "spindle"),
        ("naïve café", "naive cafe"),
    ])
    func foldsCaseDiacriticsAndWidth(_ input: String, _ expected: String) {
        #expect(TextFolding.fold(input) == expected)
    }

    @Test
    func collapsesWhitespaceAndLineBreaks() {
        #expect(TextFolding.fold("  let x =\n\n\t42  ") == "let x = 42")
    }

    @Test
    func foldingIsIdempotent() {
        let samples = ["Crème Brûlée", "東京タワー", "  a\u{00A0}b ", "👨‍👩‍👧 family"]
        for sample in samples {
            let once = TextFolding.fold(sample)
            #expect(TextFolding.fold(once) == once)
        }
    }

    @Test
    func leavesCJKAlone() {
        #expect(TextFolding.fold("東京タワーの夜景") == "東京タワーの夜景")
    }

    @Test
    func respectsTheByteLimitWithoutSplittingCharacters() {
        let text = String(repeating: "é", count: 10) + "👍🏽" + String(repeating: "x", count: 10)
        for limit in 1...40 {
            let folded = TextFolding.fold(text, maxUTF8Bytes: limit)
            #expect(folded.utf8.count <= limit)
            #expect(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).hasPrefix(folded))
        }
    }

    @Test
    func handlesHugeInputQuickly() {
        let huge = String(repeating: "lorem ipsum ", count: 1_000_000)
        let start = ContinuousClock.now
        let folded = TextFolding.fold(huge)
        #expect(folded.utf8.count <= TextFolding.searchTextLimit)
        #expect(ContinuousClock.now - start < .milliseconds(100))
    }
}

@Suite
struct PreviewTests {
    @Test
    func removesObjectReplacementCharacters() {
        #expect(TextFolding.preview(of: "photo\u{FFFC}\u{FFFC} caption") == "photo caption")
    }

    @Test
    func turnsLineBreaksIntoSpaces() {
        #expect(TextFolding.preview(of: "first line\nsecond line\r\n\tthird") == "first line second line third")
    }

    @Test
    func stripsBidiOverridesThatCouldDisguiseText() {
        #expect(TextFolding.preview(of: "invoice\u{202E}fdp.exe") == "invoicefdp.exe")
    }

    @Test
    func keepsJoinersThatEmojiAndPersianNeed() {
        let family = "👨‍👩‍👧"
        #expect(TextFolding.preview(of: family) == family)
        #expect(TextFolding.preview(of: family).count == 1)
        let persian = "می\u{200C}خواهم"
        #expect(TextFolding.preview(of: persian) == persian)
    }

    @Test
    func shortensLongTextWithAnEllipsis() {
        let preview = TextFolding.preview(of: String(repeating: "word ", count: 200), maxCharacters: 50)
        #expect(preview.count <= 50)
        #expect(preview.hasSuffix("…"))
        #expect(!preview.hasSuffix(" …"))
    }

    @Test
    func leavesShortTextUntouched() {
        #expect(TextFolding.preview(of: "https://example.org/a?b=c") == "https://example.org/a?b=c")
    }

    @Test(arguments: ["", "   ", "\n\n", "\u{FFFC}"])
    func blankInputGivesAnEmptyPreview(_ input: String) {
        #expect(TextFolding.preview(of: input).isEmpty)
    }
}
