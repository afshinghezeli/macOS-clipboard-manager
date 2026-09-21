import AppKit

/// The menu bar icon and its menu.
@MainActor
public final class StatusItemController {
    private let statusItem: NSStatusItem

    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "list.clipboard",
            accessibilityDescription: String(
                localized: "Clipboard history",
                bundle: .spindleUI,
                comment: "Accessibility description of the menu bar icon."
            )
        )
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            withTitle: String(localized: "Quit Spindle", bundle: .spindleUI, comment: "Menu bar menu item."),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }
}
