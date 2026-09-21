public import AppKit

/// What the menu bar menu shows. Read each time the menu opens.
public struct StatusMenuState {
    /// `nil` while the history is loading, or if it couldn't be opened.
    public var itemCount: Int?
    public var isPaused: Bool
    public var isSkippingNextCopy: Bool
    /// The character and modifiers of the shortcut that opens the panel, shown next to "Open Spindle".
    public var openShortcut: (key: String, modifiers: NSEvent.ModifierFlags)?

    public init(
        itemCount: Int?, isPaused: Bool, isSkippingNextCopy: Bool = false,
        openShortcut: (key: String, modifiers: NSEvent.ModifierFlags)? = nil
    ) {
        self.itemCount = itemCount
        self.isPaused = isPaused
        self.isSkippingNextCopy = isSkippingNextCopy
        self.openShortcut = openShortcut
    }
}

/// What the menu bar icon and its menu can do.
public struct StatusMenuActions {
    public var togglePanel: @MainActor () -> Void
    public var togglePause: @MainActor () -> Void
    public var skipNextCopy: @MainActor () -> Void
    /// `nil` hides "Settings…".
    public var openSettings: (@MainActor () -> Void)?

    public init(
        togglePanel: @escaping @MainActor () -> Void,
        togglePause: @escaping @MainActor () -> Void,
        skipNextCopy: @escaping @MainActor () -> Void,
        openSettings: (@MainActor () -> Void)? = nil
    ) {
        self.togglePanel = togglePanel
        self.togglePause = togglePause
        self.skipNextCopy = skipNextCopy
        self.openSettings = openSettings
    }
}

/// The menu bar icon: a click opens the panel, a right-click (or ⌃-click) shows the menu.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let state: @MainActor () -> StatusMenuState
    private let actions: StatusMenuActions
    private let menu = NSMenu()

    public init(state: @escaping @MainActor () -> StatusMenuState, actions: StatusMenuActions) {
        self.state = state
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        menu.delegate = self
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "list.clipboard",
                accessibilityDescription: String(
                    localized: "Clipboard history", bundle: .spindleUI,
                    comment: "Accessibility description of the menu bar icon."))
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            // Attach the menu only for this click, so a left click can do something else.
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            actions.togglePanel()
        }
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        let current = state()
        menu.removeAllItems()

        let open = item(
            String(
                localized: "Open Spindle", bundle: .spindleUI, comment: "Menu bar menu item; opens the history panel."),
            #selector(openChosen))
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
        menu.addItem(
            item(
                current.isPaused
                    ? String(localized: "Resume Capture", bundle: .spindleUI, comment: "Menu item; capture is paused.")
                    : String(
                        localized: "Pause Capture", bundle: .spindleUI, comment: "Menu item; stops recording copies."),
                #selector(pauseChosen)))
        let skip = item(
            String(
                localized: "Ignore Next Copy", bundle: .spindleUI, comment: "Menu item; the next copy isn't recorded."),
            #selector(skipChosen))
        skip.state = current.isSkippingNextCopy ? .on : .off
        skip.isEnabled = !current.isPaused
        menu.addItem(skip)

        menu.addItem(.separator())
        if actions.openSettings != nil {
            let settings = item(
                String(localized: "Settings…", bundle: .spindleUI, comment: "Menu item; opens the settings window."),
                #selector(settingsChosen))
            settings.keyEquivalent = ","
            menu.addItem(settings)
        }
        menu.addItem(
            withTitle: String(localized: "Quit Spindle", bundle: .spindleUI, comment: "Menu bar menu item."),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openChosen() { actions.togglePanel() }
    @objc private func pauseChosen() { actions.togglePause() }
    @objc private func skipChosen() { actions.skipNextCopy() }
    @objc private func settingsChosen() { actions.openSettings?() }

    private static func countTitle(_ count: Int?) -> String {
        guard let count else {
            return String(localized: "History unavailable", bundle: .spindleUI, comment: "Menu bar menu; no count.")
        }
        return String(
            localized: "\(count) items", bundle: .spindleUI, comment: "Menu bar menu; number of history items.")
    }
}
