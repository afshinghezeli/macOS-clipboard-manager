import Foundation
import SpindleCore
import SpindleStorage
import Testing

@testable import SpindleUI

@MainActor
@Suite
struct PanelModelTests {
    private let database: AppDatabase
    private let ingestor: Ingestor
    private let history: HistoryStore
    private let model: PanelModel

    init() throws {
        database = try AppDatabase.inMemory()
        let blobs = BlobStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "blobs-\(UUID().uuidString)"))
        ingestor = Ingestor(database: database, blobs: blobs)
        history = HistoryStore(database: database)
        model = PanelModel(history: history, pageSize: 30)
    }

    @discardableResult
    private func add(_ text: String) async throws -> Int64 {
        let item = CapturedItem(representations: [Representation(flavor: .plainText, data: Data(text.utf8))])
        let outcome = try await ingestor.ingest(
            CapturedCopy(
                items: [item], declaredTypes: [.plainText], sourceBundleID: nil, changeCount: 1, capturedAt: .now))
        switch outcome {
        case .inserted(let id), .bumped(let id): return id
        case .skipped: throw CancellationError()
        }
    }

    private func pin(_ id: Int64) async throws {
        try await history.setPinned(id, true)
    }

    @Test
    func showsPinnedItemsFirstAndSelectsTheTop() async throws {
        let pinned = try await add("pinned")
        try await add("older")
        try await add("newest")
        try await pin(pinned)
        await model.reload()
        #expect(model.items.map(\.preview) == ["pinned", "newest", "older"])
        #expect(model.selectedItem?.preview == "pinned")
    }

    @Test
    func movingTheSelectionStopsAtTheEnds() async throws {
        for text in ["a", "b", "c"] { try await add(text) }
        await model.reload()
        model.moveSelection(by: -1)
        #expect(model.selectedIndex == 0)
        model.moveSelection(by: 1)
        model.moveSelection(by: 5)
        #expect(model.selectedIndex == 2)
    }

    @Test
    func loadsTheNextPageNearTheEnd() async throws {
        for index in 1...70 { try await add("item \(index)") }
        await model.reload()
        #expect(model.items.count == 30)
        model.select(model.items[25].id)
        await model.loadMoreIfNeeded()
        #expect(model.items.count == 60)
        #expect(model.items.map(\.id).count == Set(model.items.map(\.id)).count)
    }

    @Test
    func newCopiesAppearBelowPinnedItemsWhileOpen() async throws {
        let pinned = try await add("pinned")
        try await pin(pinned)
        try await add("older")
        await model.reload()
        let selected = model.selectedID

        let fresh = try await add("fresh copy")
        await model.apply(.inserted(itemID: fresh))
        #expect(model.items.map(\.preview) == ["pinned", "fresh copy", "older"])
        #expect(model.selectedID == selected)
    }

    @Test
    func aRepeatedCopyMovesUpInsteadOfAppearingTwice() async throws {
        let first = try await add("first")
        try await add("second")
        await model.reload()
        #expect(model.items.map(\.preview) == ["second", "first"])
        try await add("first")
        await model.apply(.bumped(itemID: first))
        #expect(model.items.map(\.preview) == ["first", "second"])
    }

    @Test
    func openingResetsTheQueryAndKeepsTheOldListUntilRefreshed() async throws {
        try await add("kept")
        await model.reload()
        model.query = "leftover"
        model.panelWillOpen()
        #expect(model.query.isEmpty)
        #expect(model.items.map(\.preview) == ["kept"])
    }
}
