import Foundation
import Testing

@testable import SpindleCore

@Suite
struct CapturedCopyTests {
    private func copy(_ items: [CapturedItem], declaring extra: [PasteboardFlavor] = []) -> CapturedCopy {
        let declared = items.flatMap { $0.representations.map(\.flavor) } + extra
        return CapturedCopy(
            items: items, declaredTypes: declared, sourceBundleID: nil, changeCount: 1, capturedAt: .now)
    }

    private func text(_ string: String) -> Representation {
        Representation(flavor: .plainText, data: Data(string.utf8))
    }

    @Test
    func plainTextComesFromTheFirstItemThatHasIt() {
        let image = CapturedItem(representations: [Representation(flavor: .png, data: Data([0x89, 0x50]))])
        let caption = CapturedItem(representations: [text("Sunset over the harbor")])
        #expect(copy([image, caption]).plainText == "Sunset over the harbor")
    }

    @Test
    func plainTextIsNilWithoutATextFlavor() {
        let image = CapturedItem(representations: [Representation(flavor: .png, data: Data([0x89]))])
        #expect(copy([image]).plainText == nil)
    }

    @Test
    func byteCountAddsUpEveryRepresentation() {
        let item = CapturedItem(representations: [
            text("hello"), Representation(flavor: .rtf, data: Data(count: 100)),
        ])
        #expect(copy([item, item]).byteCount == 210)
    }

    @Test
    func privacyMarkersAreFoundAmongDeclaredTypes() {
        let item = CapturedItem(representations: [text("hunter2")])
        let marked = copy([item], declaring: [.concealed, PasteboardFlavor("com.agilebits.onepassword")])
        #expect(marked.privacyMarkers == [.concealed, PasteboardFlavor("com.agilebits.onepassword")])
        #expect(copy([item]).privacyMarkers.isEmpty)
    }

    @Test
    func universalClipboardCopiesAreRemote() {
        let item = CapturedItem(representations: [text("from my phone")])
        #expect(copy([item], declaring: [.remoteClipboard]).isRemote)
        #expect(!copy([item]).isRemote)
    }

    @Test
    func aCopyWithoutRepresentationsIsEmpty() {
        #expect(copy([CapturedItem(representations: [])]).isEmpty)
        #expect(!copy([CapturedItem(representations: [text("x")])]).isEmpty)
    }
}

@Suite
struct PasteboardFlavorTests {
    @Test
    func capturedFlavorsAreUniqueAndNeverMarkers() {
        #expect(Set(PasteboardFlavor.captured).count == PasteboardFlavor.captured.count)
        #expect(PasteboardFlavor.privacyMarkers.isDisjoint(with: PasteboardFlavor.captured))
    }

    @Test
    func plainTextIsPreferredOverEveryOtherFlavor() {
        #expect(PasteboardFlavor.captured.first == .plainText)
    }

    @Test
    func pngIsPreferredOverTiff() throws {
        let png = try #require(PasteboardFlavor.captured.firstIndex(of: .png))
        let tiff = try #require(PasteboardFlavor.captured.firstIndex(of: .tiff))
        #expect(png < tiff)
    }

    @Test(arguments: [PasteboardFlavor.png, .tiff, .jpeg, .heic, .pdf])
    func imagesMayBeLargerThanText(_ flavor: PasteboardFlavor) {
        #expect(flavor.captureLimit > PasteboardFlavor.plainText.captureLimit)
    }

    @Test(arguments: [PasteboardFlavor.fileURL, .url, .color])
    func referencesAreSmall(_ flavor: PasteboardFlavor) {
        #expect(flavor.captureLimit <= 64 << 10)
    }
}

@Suite
struct ItemKindTests {
    // These numbers are stored in every user's database. Renumbering a case would silently change
    // the kind of existing items, so this test pins them.
    @Test
    func rawValuesAreStable() {
        #expect(ItemKind.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5])
        #expect(ItemKind.text.rawValue == 0)
        #expect(ItemKind.color.rawValue == 5)
    }
}
