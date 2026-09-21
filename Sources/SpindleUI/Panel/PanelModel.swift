public import AppKit
public import Observation
import SpindleCore
public import SpindleStorage

/// How a chosen item goes back out.
public enum PasteMode: Hashable, Sendable {
    /// Paste into the app that was in front, with every format the item has.
    case paste
    /// Paste only the plain text.
    case pasteAsPlainText
    /// Put it on the clipboard and paste nothing.
    case copy
}

/// Everything the panel shows and does, independent of its views, so it can be tested without a
/// window.
@MainActor
@Observable
public final class PanelModel {
    public var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }

    /// What the list shows: search results while searching, otherwise pinned items followed by the
    /// rest of the history, newest first.
    public private(set) var items: [ItemSummary] = []

    /// Kept by id rather than position, so it stays on the same item when new copies arrive.
    public private(set) var selectedID: Int64? {
        didSet { if selectedID != oldValue { loadPreview() } }
    }

    /// The selected item in full, once loaded. `nil` while loading, so the preview never shows the
    /// previous item's contents under the new selection.
    public private(set) var preview: ItemDetails?
    /// The selected image, scaled down for the preview pane.
    public private(set) var previewImage: NSImage?

    /// Increases every time the panel opens; views watch it to reset focus and scroll position.
    public private(set) var openCount = 0

    /// Called with the chosen item. The app writes it to the clipboard and, unless copying,
    /// pastes it into the app that was in front.
    @ObservationIgnored public var onPaste: ((ItemSummary, PasteMode) -> Void)?
    /// Called when the panel should close.
    @ObservationIgnored public var onClose: (() -> Void)?

    @ObservationIgnored let history: HistoryStore?
    @ObservationIgnored private let search: SearchEngine?
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var historyItems: [ItemSummary] = []
    @ObservationIgnored private var pinnedCount = 0
    @ObservationIgnored private var hasMorePages = true
    @ObservationIgnored private var isLoadingPage = false
    @ObservationIgnored private var refresh: Task<Void, Never>?
    @ObservationIgnored private(set) var searchTask: Task<Void, Never>?
    @ObservationIgnored private var lastSearchDuration: Duration = .zero
    @ObservationIgnored private(set) var previewTask: Task<Void, Never>?

    /// - Parameters:
    ///   - history: `nil` gives an empty model, for snapshots and previews.
    ///   - search: `nil` disables searching.
    public init(history: HistoryStore? = nil, search: SearchEngine? = nil, pageSize: Int = 100) {
        self.history = history
        self.search = search
        self.pageSize = pageSize
    }

    public var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return items.firstIndex { $0.id == selectedID }
    }

    public var selectedItem: ItemSummary? {
        selectedIndex.map { items[$0] }
    }

    /// Call right before the panel appears. It shows what it already has immediately and refreshes
    /// in the background, so opening never waits for the database.
    public func panelWillOpen() {
        query = ""
        openCount += 1
        selectedID = items.first?.id
        refresh?.cancel()
        refresh = Task { await reload() }
    }

    /// Replaces the history with pinned items and the first page, and selects the first item.
    public func reload() async {
        guard let history else { return }
        do {
            let pinned = try await history.pinned()
            let recent = try await history.recent(limit: pageSize)
            try Task.checkCancellation()
            historyItems = pinned + recent
            pinnedCount = pinned.count
            hasMorePages = recent.count == pageSize
            if !isSearching { showHistory() }
        } catch {
            // A failed refresh keeps the previous list; the next open tries again.
        }
    }

    private func showHistory() {
        items = historyItems
        selectedID = items.first?.id
    }

    // MARK: - Commands

    /// Performs a keyboard command. Returns `false` when it doesn't apply, so the key can go
    /// elsewhere.
    @discardableResult
    public func handle(_ command: PanelCommand) -> Bool {
        switch command {
        case .moveUp: moveSelection(by: -1)
        case .moveDown: moveSelection(by: 1)
        case .pageUp: moveSelection(by: -8)
        case .pageDown: moveSelection(by: 8)
        case .paste: return choose(selectedItem, .paste)
        case .pasteAsPlainText: return choose(selectedItem, .pasteAsPlainText)
        case .copy: return choose(selectedItem, .copy)
        case .quickPaste(let index): return choose(items.indices.contains(index) ? items[index] : nil, .paste)
        case .escape:
            if query.isEmpty { onClose?() } else { query = "" }
        case .showActions, .togglePin, .delete, .nextFilter:
            return false
        }
        return true
    }

    private func choose(_ item: ItemSummary?, _ mode: PasteMode) -> Bool {
        guard let item else { return false }
        onPaste?(item, mode)
        return true
    }

    // MARK: - Selection

    public func select(_ id: Int64?) {
        selectedID = id
        Task { await loadMoreIfNeeded() }
    }

    /// Moves the selection by `offset` rows, stopping at either end.
    public func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        let current = selectedIndex ?? (offset > 0 ? -1 : items.count)
        let target = min(max(current + offset, 0), items.count - 1)
        select(items[target].id)
    }

    /// Loads the next page once the selection comes within a few rows of the end of the history.
    func loadMoreIfNeeded() async {
        guard let history, !isSearching, hasMorePages, !isLoadingPage, let index = selectedIndex,
            index >= items.count - 20
        else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        let lastSeq = historyItems[pinnedCount...].last?.seq
        guard let page = try? await history.recent(before: lastSeq, limit: pageSize) else { return }
        let known = Set(historyItems.map(\.id))
        historyItems.append(contentsOf: page.filter { !known.contains($0.id) })
        hasMorePages = page.count == pageSize
        if !isSearching { items = historyItems }
    }

    // MARK: - Preview

    private func loadPreview() {
        previewTask?.cancel()
        preview = nil
        previewImage = nil
        guard let history, let id = selectedID else { return }
        let isImage = selectedItem?.kind == .image
        previewTask = Task {
            let details = try? await history.details(for: id)
            let imageData = isImage ? try? await history.previewImage(for: id) : nil
            guard !Task.isCancelled, selectedID == id else { return }
            preview = details
            previewImage = imageData.flatMap(NSImage.init(data:))
        }
    }

    // MARK: - Search

    /// Each keystroke cancels the search before it: the latest query always wins. A short pause is
    /// added only when the previous search was slow, so typing never queues work.
    private func queryChanged() {
        searchTask?.cancel()
        guard isSearching else {
            showHistory()
            return
        }
        guard let search else { return }
        let text = query
        let delay: Duration = lastSearchDuration > .milliseconds(16) ? .milliseconds(40) : .zero
        searchTask = Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            let start = ContinuousClock.now
            guard let results = try? await search.search(text), !Task.isCancelled else { return }
            lastSearchDuration = ContinuousClock.now - start
            items = results.map(\.item)
            selectedID = items.first?.id
        }
    }

    // MARK: - Live changes

    /// Shows a copy that was stored while the panel is open: new and bumped items move to the top
    /// of the history, below the pinned ones.
    public func apply(_ change: HistoryChange) async {
        guard let history else { return }
        let id: Int64
        switch change {
        case .inserted(let itemID), .bumped(let itemID): id = itemID
        }
        guard let summary = try? await history.summary(for: id) else { return }
        if let existing = historyItems.firstIndex(where: { $0.id == id }) {
            if summary.isPinned && existing < pinnedCount {
                // Pinned items keep the place the user gave them.
                historyItems[existing] = summary
                publishHistory()
                return
            }
            historyItems.remove(at: existing)
            if existing < pinnedCount { pinnedCount -= 1 }
        }
        historyItems.insert(summary, at: pinnedCount)
        if summary.isPinned { pinnedCount += 1 }
        publishHistory()
    }

    private func publishHistory() {
        if !isSearching {
            let selected = selectedID
            items = historyItems
            selectedID = selected ?? items.first?.id
        }
    }
}
