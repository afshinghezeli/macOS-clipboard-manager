import AppKit
import SpindleCore
import Testing

@testable import SpindleSystem

/// Every test gets its own private pasteboard; the real clipboard is never touched.
@MainActor
@Suite
final class PasteboardGatewayTests {
    // `nonisolated(unsafe)` only so that deinit (nonisolated in Swift 6.1) can release it; deinit
    // runs after the test has finished, when nothing else can touch the pasteboard.
    private nonisolated(unsafe) let pasteboard = NSPasteboard.withUniqueName()
    private let safari = AppIdentity(bundleID: "com.apple.Safari", name: "Safari")

    deinit {
        pasteboard.releaseGlobally()
    }

    private func gateway(access: PasteboardAccess = .allowed) -> PasteboardGateway {
        PasteboardGateway(pasteboard: pasteboard, access: { _ in access })
    }

    private func put(_ items: [[(String, Data)]]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(
            items.map { representations in
                let item = NSPasteboardItem()
                for (type, data) in representations { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
                return item
            })
    }

    private func capturedCopy(_ read: PasteboardRead) -> CapturedCopy? {
        if case .copy(let copy) = read { return copy }
        Issue.record("expected a copy, got \(read)")
        return nil
    }

    @Test
    func readsTextAndAttributesItToTheFrontmostApp() throws {
        pasteboard.clearContents()
        pasteboard.setString("Hello from Safari", forType: .string)
        let copy = try #require(capturedCopy(gateway().read(frontmostApp: safari, at: .now)))
        #expect(copy.plainText == "Hello from Safari")
        #expect(copy.sourceBundleID == "com.apple.Safari")
        #expect(copy.sourceAppName == "Safari")
        #expect(copy.changeCount == pasteboard.changeCount)
    }

    @Test
    func doesNotReadCopiesMarkedPrivate() {
        put([[("public.utf8-plain-text", Data("hunter2".utf8)), ("org.nspasteboard.ConcealedType", Data())]])
        #expect(gateway().read(frontmostApp: safari, at: .now) == .marked)
    }

    @Test
    func doesNotReadWhenMacOSAsksOrDenies() {
        pasteboard.clearContents()
        pasteboard.setString("secret", forType: .string)
        #expect(gateway(access: .askEachTime).read(frontmostApp: safari, at: .now) == .restricted(.askEachTime))
        #expect(gateway(access: .denied).read(frontmostApp: safari, at: .now) == .restricted(.denied))
    }

    @Test
    func readsOnlyAllowListedFlavors() throws {
        put([
            [
                ("public.utf8-plain-text", Data("text".utf8)),
                ("dyn.ah62d4rv4gu8y", Data("private app data".utf8)),
                ("com.microsoft.ole.source", Data("ole".utf8)),
            ]
        ])
        let copy = try #require(capturedCopy(gateway().read(frontmostApp: safari, at: .now)))
        #expect(copy.items.first?.representations.map(\.flavor) == [.plainText])
    }

    @Test
    func skipsTIFFWhenPNGIsOffered() throws {
        put([[("public.png", Data([0x89, 0x50])), ("public.tiff", Data([0x4D, 0x4D]))]])
        let copy = try #require(capturedCopy(gateway().read(frontmostApp: safari, at: .now)))
        #expect(copy.items.first?.representations.map(\.flavor) == [.png])
    }

    @Test
    func keepsEachFileAsItsOwnItem() throws {
        let urls = ["/tmp/a.txt", "/tmp/b.txt"].map { URL(filePath: $0) }
        put(urls.map { [("public.file-url", $0.dataRepresentation)] })
        let copy = try #require(capturedCopy(gateway().read(frontmostApp: safari, at: .now)))
        #expect(copy.items.count == 2)
    }

    @Test
    func skipsPayloadsOverTheLimit() {
        let gateway = gateway()
        gateway.sizeLimit = { _ in 8 }
        pasteboard.clearContents()
        pasteboard.setString("longer than eight bytes", forType: .string)
        #expect(gateway.read(frontmostApp: safari, at: .now) == .nothingToKeep)
    }

    @Test
    func prefersTheSourceTheCopyingAppDeclares() throws {
        put([
            [
                ("public.utf8-plain-text", Data("from a background helper".utf8)),
                ("org.nspasteboard.source", Data("com.example.helper".utf8)),
            ]
        ])
        let copy = try #require(capturedCopy(gateway().read(frontmostApp: safari, at: .now)))
        #expect(copy.sourceBundleID == "com.example.helper")
        #expect(copy.sourceAppName == nil)
    }

    @Test
    func recognizesItsOwnWrites() throws {
        let gateway = gateway()
        let item = CapturedItem(representations: [Representation(flavor: .plainText, data: Data("from history".utf8))])
        gateway.write([item], sourceBundleID: "com.afshinghezeli.Spindle")
        #expect(gateway.read(frontmostApp: safari, at: .now) == .ownWrite)
        #expect(pasteboard.string(forType: .string) == "from history")

        // The next copy by someone else is read normally.
        pasteboard.clearContents()
        pasteboard.setString("someone else", forType: .string)
        #expect(capturedCopy(gateway.read(frontmostApp: safari, at: .now))?.plainText == "someone else")
    }

    @Test
    func writesEveryItemBack() {
        let gateway = gateway()
        let files = ["/tmp/a.txt", "/tmp/b.txt"].map {
            CapturedItem(representations: [Representation(flavor: .fileURL, data: URL(filePath: $0).dataRepresentation)]
            )
        }
        gateway.write(files, sourceBundleID: "com.afshinghezeli.Spindle")
        #expect(pasteboard.pasteboardItems?.count == 2)
    }
}
