public import AppKit
import SpindleSystem

/// What the menu bar menu shows. Read each time the menu opens.
public struct StatusMenuState {
    /// `nil` while the history is loading, or if it couldn't be opened.
    public var itemCount: Int?
    public var isPaused: Bool
    /// When a timed pause ends; `nil` when not paused or paused until resumed.
    public var pausedUntil: Date?
    public var isSkippingNextCopy: Bool
    /// macOS currently won't let Spindle read the clipboard.
    public var isClipboardBlocked = false
    /// The character and modifiers of the shortcut that opens the panel, shown next to "Open Spindle".
    public var openShortcut: (key: String, modifiers: NSEvent.ModifierFlags)?
    /// An update was found in the background and the user hasn't looked at it yet.
    public var isUpdatePending = false

    public init(
        itemCount: Int?, isPaused: Bool, pausedUntil: Date? = nil, isSkippingNextCopy: Bool = false,
        openShortcut: (key: String, modifiers: NSEvent.ModifierFlags)? = nil
    ) {
        self.itemCount = itemCount
        self.isPaused = isPaused
        self.pausedUntil = pausedUntil
        self.isSkippingNextCopy = isSkippingNextCopy
        self.openShortcut = openShortcut
    }
}

/// What the menu bar icon and its menu can do.
public struct StatusMenuActions {
    public var togglePanel: @MainActor () -> Void
    /// Pauses for the given time, or until resumed when `nil`.
    public var pause: @MainActor (TimeInterval?) -> Void
    public var resume: @MainActor () -> Void
    public var skipNextCopy: @MainActor () -> Void
    /// `nil` hides "Settings…".
    public var openSettings: (@MainActor () -> Void)?
    /// `nil` hides "Check for Updates…", for builds that don't update themselves.
    public var checkForUpdates: (@MainActor () -> Void)?

    public init(
        togglePanel: @escaping @MainActor () -> Void,
        pause: @escaping @MainActor (TimeInterval?) -> Void,
        resume: @escaping @MainActor () -> Void,
        skipNextCopy: @escaping @MainActor () -> Void,
        openSettings: (@MainActor () -> Void)? = nil,
        checkForUpdates: (@MainActor () -> Void)? = nil
    ) {
        self.togglePanel = togglePanel
        self.pause = pause
        self.resume = resume
        self.skipNextCopy = skipNextCopy
        self.openSettings = openSettings
        self.checkForUpdates = checkForUpdates
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
            button.image = Self.icon(withDot: false)
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Adds a dot to the icon, or removes it. The dot means an update is waiting.
    public func setShowsDot(_ showsDot: Bool) {
        statusItem.button?.image = Self.icon(withDot: showsDot)
    }

    static func icon(withDot: Bool) -> NSImage? {
        let description = String(
            localized: "Clipboard history", bundle: .spindleUI,
            comment: "Accessibility description of the menu bar icon.")
        guard let symbol = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: description)
        else { return nil }
        guard withDot else { return symbol }
        // A little wider than the symbol, so the dot sits beside the clip instead of on it.
        let size = NSSize(width: symbol.size.width + 3, height: symbol.size.height)
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
            let dot = NSRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 5, height: 5)
            // Clear a ring around the dot, so it reads as a badge and not part of the symbol.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        // A template image, so the dot follows the menu bar's color like the symbol does.
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
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
        if current.isClipboardBlocked {
            let blocked = item(
                String(
                    localized: "macOS Is Blocking Clipboard Access…", bundle: .spindleUI,
                    comment: "Menu item shown when clipboard access is blocked; opens System Settings."),
                #selector(blockedChosen))
            blocked.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(blocked)
        }
        if current.isPaused {
            menu.addItem(
                item(
                    String(localized: "Resume Capture", bundle: .spindleUI, comment: "Menu item; capture is paused."),
                    #selector(resumeChosen)))
            if let until = current.pausedUntil {
                let note = NSMenuItem(
                    title: String(
                        localized: "Paused until \(until.formatted(date: .omitted, time: .shortened))",
                        bundle: .spindleUI,
                        comment: "Menu bar menu: when a timed pause ends."),
                    action: nil, keyEquivalent: "")
                note.isEnabled = false
                menu.addItem(note)
            }
        } else {
            let pause = NSMenuItem(
                title: String(
                    localized: "Pause Capture", bundle: .spindleUI, comment: "Menu item; stops recording copies."),
                action: nil, keyEquivalent: "")
            let choices = NSMenu()
            for (title, duration) in Self.pauseChoices {
                let choice = item(title, #selector(pauseChosen(_:)))
                choice.representedObject = duration
                choices.addItem(choice)
            }
            pause.submenu = choices
            menu.addItem(pause)
        }
        let skip = item(
            String(
                localized: "Ignore Next Copy", bundle: .spindleUI, comment: "Menu item; the next copy isn't recorded."),
            #selector(skipChosen))
        skip.state = current.isSkippingNextCopy ? .on : .off
        skip.isEnabled = !current.isPaused
        menu.addItem(skip)

        menu.addItem(.separator())
        if actions.checkForUpdates != nil {
            let title =
                current.isUpdatePending
                ? String(
                    localized: "Update Available…", bundle: .spindleUI,
                    comment: "Menu item; shows the update that was found.")
                : String(
                    localized: "Check for Updates…", bundle: .spindleUI, comment: "Menu item; asks Sparkle to check.")
            menu.addItem(item(title, #selector(updatesChosen)))
        }
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
    @objc private func blockedChosen() { SystemSettingsPane.pasteboard.open() }
    @objc private func pauseChosen(_ sender: NSMenuItem) {
        actions.pause(sender.representedObject as? TimeInterval)
    }
    @objc private func resumeChosen() { actions.resume() }

    private static let pauseChoices: [(String, TimeInterval?)] = [
        (String(localized: "For 5 Minutes", bundle: .spindleUI, comment: "Pause capture choice."), 5 * 60),
        (String(localized: "For 1 Hour", bundle: .spindleUI, comment: "Pause capture choice."), 60 * 60),
        (String(localized: "Until Resumed", bundle: .spindleUI, comment: "Pause capture choice."), nil),
    ]
    @objc private func skipChosen() { actions.skipNextCopy() }
    @objc private func settingsChosen() { actions.openSettings?() }
    @objc private func updatesChosen() { actions.checkForUpdates?() }

    private static func countTitle(_ count: Int?) -> String {
        guard let count else {
            return String(localized: "History unavailable", bundle: .spindleUI, comment: "Menu bar menu; no count.")
        }
        return String(
            localized: "\(count) items", bundle: .spindleUI, comment: "Menu bar menu; number of history items.")
    }
}
