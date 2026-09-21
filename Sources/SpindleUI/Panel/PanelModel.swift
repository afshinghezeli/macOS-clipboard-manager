public import Observation
public import SpindleStorage

/// Everything the panel shows and does, independent of its views, so it can be tested without a
/// window.
@MainActor
@Observable
public final class PanelModel {
    public var query = ""

    /// Pinned items first, then the rest of the history, newest first.
    public private(set) var items: [ItemSummary] = []

    /// Kept by id rather than position, so it stays on the same item when new copies arrive.
    public private(set) var selectedID: Int64?

    /// Increases every time the panel opens; views watch it to reset focus and scroll position.
    public private(set) var openCount = 0

    @ObservationIgnored private let history: HistoryStore?
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var pinnedCount = 0
    @ObservationIgnored private var hasMorePages = true
    @ObservationIgnored private var isLoadingPage = false
    @ObservationIgnored private var refresh: Task<Void, Never>?

    /// - Parameter history: `nil` gives an empty model, for snapshots and previews.
    public init(history: HistoryStore? = nil, pageSize: Int = 100) {
        self.history = history
        self.pageSize = pageSize
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

    /// Replaces the list with pinned items and the first page of history, and selects the first.
    public func reload() async {
        guard let history else { return }
        do {
            let pinned = try await history.pinned()
            let recent = try await history.recent(limit: pageSize)
            try Task.checkCancellation()
            items = pinned + recent
            pinnedCount = pinned.count
            hasMorePages = recent.count == pageSize
            selectedID = items.first?.id
        } catch {
            // A failed refresh keeps the previous list; the next open tries again.
        }
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

    /// Loads the next page once the selection comes within a few rows of the end of the list.
    func loadMoreIfNeeded() async {
        guard let history, hasMorePages, !isLoadingPage, let index = selectedIndex, index >= items.count - 20 else {
            return
        }
        isLoadingPage = true
        defer { isLoadingPage = false }
        let lastSeq = items[pinnedCount...].last?.seq
        guard let page = try? await history.recent(before: lastSeq, limit: pageSize) else { return }
        let known = Set(items.map(\.id))
        items.append(contentsOf: page.filter { !known.contains($0.id) })
        hasMorePages = page.count == pageSize
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
        if let existing = items.firstIndex(where: { $0.id == id }) {
            if summary.isPinned {
                items[existing] = summary
                return
            }
            items.remove(at: existing)
            if existing < pinnedCount { pinnedCount -= 1 }
        }
        guard !summary.isPinned else { return }
        items.insert(summary, at: pinnedCount)
    }
}
