import AppKit
import SpindleCore
import SpindleStorage
import SpindleSystem
import Testing

@testable import SpindleUI

@MainActor
@Suite
struct PanelSnapshotTests {
    private let size = NSSize(width: 760, height: 460)

    /// A history like one a person might have after an hour of work.
    private func sampleModel() async throws -> PanelModel {
        let database = try AppDatabase.inMemory()
        let blobs = BlobStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "blobs-\(UUID().uuidString)"))
        let ingestor = Ingestor(database: database, blobs: blobs)
        let history = HistoryStore(database: database, blobs: blobs)

        func add(_ representations: [(PasteboardFlavor, Data)], items: Int = 1) async throws -> Int64? {
            let item = CapturedItem(representations: representations.map { Representation(flavor: $0.0, data: $0.1) })
            let outcome = try await ingestor.ingest(
                CapturedCopy(
                    items: Array(repeating: item, count: items), declaredTypes: representations.map(\.0),
                    sourceBundleID: "com.apple.Safari", changeCount: 1, capturedAt: .now))
            if case .inserted(let id) = outcome { return id }
            return nil
        }
        func text(_ string: String) -> (PasteboardFlavor, Data) { (.plainText, Data(string.utf8)) }

        let pinned = try await add([text("afshin@example.org")])
        _ = try await add([text("git rebase -i HEAD~3")])
        _ = try await add([text("Meeting notes\n- ship 0.1\n- write the README")])
        _ = try await add([(.fileURL, URL(filePath: "/Users/me/Documents/Budget 2026.numbers").dataRepresentation)])
        _ = try await add([text("#FF9500")])
        _ = try await add([(.png, Self.sampleImage())])
        _ = try await add([text("https://github.com/afshinghezeli/spindle")])
        _ = try await add([text("The quick brown fox jumps over the lazy dog"), (.rtf, Data("{\\rtf1 x}".utf8))])
        if let pinned { try await history.setPinned(pinned, true) }

        let model = PanelModel(history: history)
        model.targetAppName = "Safari"
        await model.reload()
        return model
    }

    private static func sampleImage() -> Data {
        let context = CGContext(
            data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.25, green: 0.5, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        return bitmap.representation(using: .png, properties: [:])!
    }

    @Test
    func emptyPanel() throws {
        try Snapshot.write(PanelView(model: PanelModel()), named: "panel-empty", size: size)
    }

    @Test
    func panelWithHistory() async throws {
        guard Snapshot.directory != nil else { return }
        let model = try await sampleModel()
        try Snapshot.write(PanelView(model: model), named: "panel-history", size: size)
        try Snapshot.write(PanelView(model: model), named: "panel-history-dark", size: size, appearance: .darkAqua)
    }

    @Test
    func previewOfEachKind() async throws {
        guard Snapshot.directory != nil else { return }
        let model = try await sampleModel()
        let picks: [(String, (ItemSummary) -> Bool)] = [
            ("text", { $0.preview.hasPrefix("Meeting notes") }),
            ("image", { $0.kind == .image }),
            ("color", { $0.kind == .color }),
            ("file", { $0.kind == .file }),
        ]
        for (name, matches) in picks {
            guard let item = model.items.first(where: matches) else {
                Issue.record("no \(name) item in the sample history")
                continue
            }
            model.select(item.id)
            await model.previewTask?.value
            try Snapshot.write(PanelView(model: model), named: "preview-\(name)", size: size)
        }
    }

    /// The README's screenshots; `make screenshots` copies them to docs/images.
    @Test
    func readmeScreenshots() async throws {
        guard Snapshot.directory != nil else { return }
        let model = try await sampleModel()
        let notes = try #require(model.items.first { $0.preview.hasPrefix("Meeting notes") })
        model.select(notes.id)
        await model.previewTask?.value
        try Snapshot.write(PanelView(model: model), named: "readme-panel-light", size: size)
        try Snapshot.write(PanelView(model: model), named: "readme-panel-dark", size: size, appearance: .darkAqua)
    }

    @Test
    func blockedClipboardBanner() async throws {
        guard Snapshot.directory != nil else { return }
        let model = try await sampleModel()
        model.clipboardAccessProblem = .denied
        try Snapshot.write(PanelView(model: model), named: "panel-blocked", size: size)
    }
}
