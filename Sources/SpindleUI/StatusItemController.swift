public import AppKit

/// What the menu bar menu shows. Read each time the menu opens.
public struct StatusMenuState {
    /// `nil` while the history is loading, or if it couldn't be opened.
    public var itemCount: Int?
    public var isPaused: Bool
    /// The character and modifiers of the shortcut that opens the panel, shown next to "Open Spindle".
    public var openShortcut: (key: String, modifiers: NSEvent.ModifierFlags)?

    public init(itemCount: Int?, isPaused: Bool, openShortcut: (key: String, modifiers: NSEvent.ModifierFlags)? = nil) {
        self.itemCount = itemCount
        self.isPaused = isPaused
        self.openShortcut = openShortcut
    }
}

/// The menu bar icon and its menu.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let state: @MainActor () -> StatusMenuState
    private let openPanel: @MainActor () -> Void
    private let togglePause: @MainActor () -> Void

    public init(
        state: @escaping @MainActor () -> StatusMenuState,
        openPanel: @escaping @MainActor () -> Void,
        togglePause: @escaping @MainActor () -> Void
    ) {
        self.state = state
        self.openPanel = openPanel
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

        let open = NSMenuItem(
            title: String(
                localized: "Open Spindle", bundle: .spindleUI, comment: "Menu bar menu item; opens the history panel."),
            action: #selector(openChosen),
            keyEquivalent: "")
        open.target = self
        if let shortcut = current.openShortcut {
            // Shown for reference; the global hotkey does the work.
            open.keyEquivalent = shortcut.key
            open.keyEquivalentModifierMask = shortcut.modifiers
        }
        menu.addItem(open)
        menu.addItem(.separator())

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

    @objc private func openChosen() {
        openPanel()
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
