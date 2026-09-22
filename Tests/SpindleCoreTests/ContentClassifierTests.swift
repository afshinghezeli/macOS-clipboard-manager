import Foundation
import Testing

@testable import SpindleCore

@Suite
struct TextShapeTests {
    @Test(arguments: [
        "https://github.com/afshinghezeli/spindle",
        "http://localhost:8080/health",
        "  https://example.org/path?q=1#frag  ",
        "ftp://files.example.org/pub",
    ])
    func recognizesWebLinks(_ text: String) {
        guard case .link = ContentClassifier.shape(of: text) else {
            Issue.record("\(text) should be a link")
            return
        }
    }

    @Test(arguments: [
        "example.org",  // no scheme
        "javascript:alert(1)",  // not a web scheme
        "https://example.org and more words",
        "https://",
    ])
    func rejectsThingsThatAreNotWebLinks(_ text: String) {
        if case .link = ContentClassifier.shape(of: text) {
            Issue.record("\(text) should not be a link")
        }
    }

    @Test(arguments: [
        "#1E90FF", "#fff", "#ffff", "#1e90ff80", "rgb(30, 144, 255)", "rgba(30 144 255 / 50%)",
        "hsl(210deg, 100%, 56%)",
    ])
    func recognizesColors(_ text: String) {
        #expect(ContentClassifier.shape(of: text) == .color)
    }

    @Test(arguments: ["facade", "123", "#12345", "#ggg", "rgb(1, 2)", "rgb(a, b, c)", "hsl()"])
    func rejectsNearMissColors(_ text: String) {
        #expect(ContentClassifier.shape(of: text) != .color)
    }

    @Test(arguments: ["someone@example.org", "mailto:someone@example.org", "first.last+tag@sub.example.co.uk"])
    func recognizesEmailAddresses(_ text: String) {
        #expect(ContentClassifier.shape(of: text) == .email)
    }

    @Test(arguments: ["@handle", "a@b", "two@at@signs.org", "someone@example.org is here"])
    func rejectsNearMissEmailAddresses(_ text: String) {
        #expect(ContentClassifier.shape(of: text) != .email)
    }

    @Test(arguments: ["/usr/local/bin/swift", "~/Library/Containers", "/Applications/Spindle.app"])
    func recognizesFilePaths(_ text: String) {
        #expect(ContentClassifier.shape(of: text) == .filePath)
    }

    @Test(arguments: ["/", "// comment", "usr/local"])
    func rejectsNearMissFilePaths(_ text: String) {
        #expect(ContentClassifier.shape(of: text) != .filePath)
    }

    @Test
    func multilineTextIsAlwaysPlain() {
        #expect(ContentClassifier.shape(of: "https://example.org\nhttps://example.com") == .plain)
    }

    @Test
    func longTextIsAlwaysPlain() {
        let long = "https://example.org/" + String(repeating: "a", count: 3000)
        #expect(ContentClassifier.shape(of: long) == .plain)
    }
}

@Suite
struct ItemKindClassificationTests {
    private func copy(_ flavors: [(PasteboardFlavor, String)], items: Int = 1) -> CapturedCopy {
        let item = CapturedItem(representations: flavors.map { Representation(flavor: $0.0, data: Data($0.1.utf8)) })
        return CapturedCopy(
            items: Array(repeating: item, count: items),
            declaredTypes: flavors.map(\.0),
            sourceBundleID: nil,
            changeCount: 1,
            capturedAt: .now
        )
    }

    @Test
    func finderFilesAreFiles() {
        let files = copy([(.fileURL, "file:///Users/me/a.pdf"), (.plainText, "a.pdf")], items: 3)
        #expect(ContentClassifier.kind(of: files) == .file)
    }

    @Test
    func anImageWithoutTextIsAnImage() {
        #expect(ContentClassifier.kind(of: copy([(.png, "png"), (.html, "<img>")])) == .image)
        #expect(ContentClassifier.kind(of: copy([(.pdf, "%PDF")])) == .image)
    }

    @Test
    func spreadsheetCellsAreTextEvenWithAPicture() {
        let cells = copy([(.plainText, "Q1\t120\nQ2\t140"), (.html, "<table>"), (.png, "png")])
        #expect(ContentClassifier.kind(of: cells) == .richText)
    }

    @Test
    func aURLStringIsALink() {
        #expect(ContentClassifier.kind(of: copy([(.plainText, "https://swift.org")])) == .link)
    }

    @Test
    func aHexStringIsAColor() {
        #expect(ContentClassifier.kind(of: copy([(.plainText, "#FF9500")])) == .color)
    }

    @Test
    func aColorFlavorWithoutTextIsAColor() {
        #expect(ContentClassifier.kind(of: copy([(.color, "archived NSColor")])) == .color)
    }

    @Test
    func formattedTextIsRichText() {
        #expect(ContentClassifier.kind(of: copy([(.plainText, "Hello"), (.rtf, "{\\rtf1 Hello}")])) == .richText)
    }

    @Test
    func plainTextIsText() {
        #expect(ContentClassifier.kind(of: copy([(.plainText, "Hello")])) == .text)
    }
}
