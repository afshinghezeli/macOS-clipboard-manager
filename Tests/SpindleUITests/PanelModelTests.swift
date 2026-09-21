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
        history = HistoryStore(database: database, blobs: blobs)
        model = PanelModel(history: history, search: SearchEngine(database: database), pageSize: 30)
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

    // MARK: - Search and commands

    private func search(_ text: String) async {
        model.query = text
        await model.searchTask?.value
    }

    @Test
    func typingSearchesAndClearingShowsTheHistoryAgain() async throws {
        for text in ["git status", "invoice 2026", "git log"] { try await add(text) }
        await model.reload()
        await search("git")
        #expect(Set(model.items.map(\.preview)) == ["git status", "git log"])
        #expect(model.selectedIndex == 0)
        await search("")
        #expect(model.items.count == 3)
    }

    @Test
    func theLatestQueryWins() async throws {
        for text in ["alpha", "beta"] { try await add(text) }
        await model.reload()
        model.query = "alp"
        model.query = "bet"
        await model.searchTask?.value
        #expect(model.items.map(\.preview) == ["beta"])
    }

    @Test
    func escapeClearsTheSearchThenCloses() async throws {
        var closed = false
        model.onClose = { closed = true }
        model.query = "something"
        model.handle(.escape)
        #expect(model.query.isEmpty)
        #expect(!closed)
        model.handle(.escape)
        #expect(closed)
    }

    @Test
    func returnPastesTheSelectionInTheChosenMode() async throws {
        for text in ["first", "second"] { try await add(text) }
        await model.reload()
        var chosen: [(String, PasteMode)] = []
        model.onPaste = { chosen.append(($0.preview, $1)) }
        model.handle(.moveDown)
        model.handle(.paste)
        model.handle(.pasteAsPlainText)
        model.handle(.copy)
        #expect(chosen.map(\.0) == ["first", "first", "first"])
        #expect(chosen.map(\.1) == [.paste, .pasteAsPlainText, .copy])
    }

    @Test
    func numberShortcutsPasteByPosition() async throws {
        for text in ["one", "two", "three"] { try await add(text) }
        await model.reload()
        var pasted: [String] = []
        model.onPaste = { item, _ in pasted.append(item.preview) }
        #expect(model.handle(.quickPaste(2)))
        #expect(!model.handle(.quickPaste(7)))
        #expect(pasted == ["one"])
    }

    @Test
    func nothingToPasteInAnEmptyList() {
        #expect(!model.handle(.paste))
    }

    @Test
    func selectingAnItemLoadsItsPreview() async throws {
        let first = try await add("first line\nsecond line")
        try await add("other")
        await model.reload()
        model.select(first)
        #expect(model.preview == nil)  // never the previous item's contents meanwhile
        await model.previewTask?.value
        #expect(model.preview?.summary.id == first)
        #expect(model.preview?.text == "first line\nsecond line")
    }

    // MARK: - Pins and deleting

    @Test
    func pinningMovesTheItemIntoThePinnedGroupAndKeepsItSelected() async throws {
        for text in ["a", "b", "c"] { try await add(text) }
        await model.reload()
        model.moveSelection(by: 2)  // "a"
        model.handle(.togglePin)
        await model.pendingChange?.value
        #expect(model.items.map(\.preview) == ["a", "c", "b"])
        #expect(model.selectedItem?.preview == "a")
        #expect(model.selectedItem?.isPinned == true)
        model.handle(.togglePin)
        await model.pendingChange?.value
        #expect(model.items.map(\.preview) == ["c", "b", "a"])
    }

    @Test
    func deletingSelectsTheNextItem() async throws {
        for text in ["a", "b", "c"] { try await add(text) }
        await model.reload()
        model.moveSelection(by: 1)  // "b"
        model.handle(.delete)
        await model.pendingChange?.value
        #expect(model.items.map(\.preview) == ["c", "a"])
        #expect(model.selectedItem?.preview == "a")
    }

    @Test
    func reorderingOnlyAppliesToPinnedItems() async throws {
        let a = try await add("a")
        let b = try await add("b")
        try await pin(a)
        try await pin(b)
        await model.reload()
        model.select(b)
        #expect(model.handle(.movePinUp))
        await model.pendingChange?.value
        #expect(model.items.prefix(2).map(\.preview) == ["b", "a"])
        try await add("loose")
        await model.reload()
        model.select(model.items.first { !$0.isPinned }?.id)
        #expect(!model.handle(.movePinUp))
    }
}
