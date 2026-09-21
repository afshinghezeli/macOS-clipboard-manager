public import AppKit

/// What the menu bar menu shows. Read each time the menu opens.
public struct StatusMenuState: Sendable {
    /// `nil` while the history is loading, or if it couldn't be opened.
    public var itemCount: Int?
    public var isPaused: Bool

    public init(itemCount: Int?, isPaused: Bool) {
        self.itemCount = itemCount
        self.isPaused = isPaused
    }
}

/// The menu bar icon and its menu.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let state: @MainActor () -> StatusMenuState
    private let togglePause: @MainActor () -> Void

    public init(
        state: @escaping @MainActor () -> StatusMenuState,
        togglePause: @escaping @MainActor () -> Void
    ) {
        self.state = state
        self.togglePause = togglePause
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "list.clipboard",
            accessibilityDescription: String(
                localized: "Clipboard history", bundle: .spindleUI,
                comment: "Accessibility description of the menu bar icon."))
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        let current = state()
        menu.removeAllItems()

        let count = NSMenuItem(title: Self.countTitle(current.itemCount), action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)

        let pause = NSMenuItem(
            title: current.isPaused
                ? String(localized: "Resume Capture", bundle: .spindleUI, comment: "Menu item; capture is paused.")
                : String(localized: "Pause Capture", bundle: .spindleUI, comment: "Menu item; stops recording copies."),
            action: #selector(pauseChosen),
            keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Quit Spindle", bundle: .spindleUI, comment: "Menu bar menu item."),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
    }

    @objc private func pauseChosen() {
        togglePause()
    }

    private static func countTitle(_ count: Int?) -> String {
        guard let count else {
            return String(localized: "History unavailable", bundle: .spindleUI, comment: "Menu bar menu; no count.")
        }
        return String(
            localized: "\(count) items", bundle: .spindleUI, comment: "Menu bar menu; number of history items.")
    }
}
