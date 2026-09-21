import AppKit
import SpindleStorage
import SwiftUI

/// The history list: an `NSTableView` behind SwiftUI (ADR 0005).
///
/// Moving the selection costs the same with 100 or 100,000 rows, which SwiftUI's `List` doesn't
/// manage on macOS 15. The table never takes keyboard focus; the search field routes arrow keys to
/// the model instead.
struct HistoryTableView: NSViewRepresentable {
    var items: [ItemSummary]
    var selectedID: Int64?
    var thumbnails: ThumbnailCache
    var onSelect: (Int64) -> Void
    var onActivate: (Int64) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = FocuslessTableView()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item")))
        table.headerView = nil
        table.rowHeight = ItemCellView.rowHeight
        table.usesAutomaticRowHeights = false
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .inset
        table.backgroundColor = .clear
        table.allowsTypeSelect = false
        table.allowsEmptySelection = true
        table.focusRingType = .none
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.activated(_:))

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let table = coordinator.table else { return }
        let ids = items.map(\.id)
        if ids != coordinator.ids || items != coordinator.items {
            coordinator.ids = ids
            coordinator.items = items
            table.reloadData()
        }
        coordinator.isSyncingSelection = true
        defer { coordinator.isSyncingSelection = false }
        if let selectedID, let row = ids.firstIndex(of: selectedID) {
            if table.selectedRow != row {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            table.scrollRowToVisible(row)
        } else {
            table.deselectAll(nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: HistoryTableView?
        weak var table: NSTableView?
        var items: [ItemSummary] = []
        var ids: [Int64] = []
        var isSyncingSelection = false

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cell =
                tableView.makeView(withIdentifier: ItemCellView.identifier, owner: nil) as? ItemCellView
                ?? ItemCellView(frame: .zero)
            if let parent { cell.configure(with: items[row], thumbnails: parent.thumbnails) }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let table, table.selectedRow >= 0 else { return }
            parent?.onSelect(items[table.selectedRow].id)
        }

        @objc func activated(_ sender: NSTableView) {
            guard sender.clickedRow >= 0, sender.clickedRow < items.count else { return }
            parent?.onActivate(items[sender.clickedRow].id)
        }
    }
}

/// Keeps keyboard focus in the search field when a row is clicked.
private final class FocuslessTableView: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}
