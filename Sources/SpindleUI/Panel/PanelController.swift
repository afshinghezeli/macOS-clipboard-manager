import AppKit
public import SwiftUI

/// Shows and hides the history panel.
///
/// The window and its views are built once, at launch, so opening the panel never waits for them.
@MainActor
public final class PanelController {
    private let window: PanelWindow

    /// Called after the panel hides, however that happened.
    public var onHide: (() -> Void)?

    /// Handles ⌘ shortcuts pressed in the panel; see ``PanelKeyMap``.
    public var onCommand: ((PanelCommand) -> Bool)?

    public init(rootView: some View) {
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        window = PanelWindow(contentView: Self.background(around: hosting))
        window.onResignKey = { [weak self] in
            guard let self, self.window.attachedSheet == nil, !self.isShowingMenu else { return }
            self.hide()
        }
        window.onCancel = { [weak self] in self?.hide() }
        window.onKeyEquivalent = { [weak self] event in
            guard let characters = event.charactersIgnoringModifiers,
                let command = PanelKeyMap.command(forKeyEquivalent: characters, modifiers: event.modifierFlags)
            else { return false }
            return self?.onCommand?(command) ?? false
        }
    }

    private var isShowingMenu = false
    private var lastHide = Date.distantPast

    /// True just after the panel closed. Clicking the menu bar icon while the panel is open first
    /// takes focus from the panel, which closes it, and then delivers the click; that click must
    /// not open the panel again.
    public var didJustHide: Bool { Date.now.timeIntervalSince(lastHide) < 0.3 }

    public var isVisible: Bool { window.isVisible }

    /// The panel's backdrop: Liquid Glass on macOS 26 and later, the translucent popover material
    /// before that, and a plain window background when Reduce Transparency is on.
    private static func background(around content: NSView) -> NSView {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let plain = NSView()
            plain.wantsLayer = true
            plain.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            return embed(content, in: plain)
        }
        #if compiler(>=6.2)
        // Needs the macOS 26 SDK, which the Command Line Tools on older macOS don't have; CI's
        // newest-Xcode job builds this branch.
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 16
            glass.contentView = content
            return glass
        }
        #endif
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        // The panel never makes Spindle the active app, and the default `.followsWindowActiveState`
        // would then render it flat.
        material.state = .active
        return embed(content, in: material)
    }

    private static func embed(_ content: NSView, in container: NSView) -> NSView {
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    /// Shows `actions` as a menu at the bottom right of the panel, and performs the chosen one.
    public func showActionsMenu(_ actions: [PanelAction], perform: @escaping (PanelCommand) -> Void) {
        guard let contentView = window.contentView else { return }
        let menu = NSMenu()
        let handler = MenuHandler(perform: perform)
        for action in actions {
            let item = NSMenuItem(
                title: action.title, action: #selector(MenuHandler.chosen(_:)), keyEquivalent: action.keyEquivalent)
            item.keyEquivalentModifierMask = action.modifiers
            item.representedObject = action.command
            item.target = handler
            menu.addItem(item)
        }
        isShowingMenu = true
        defer { isShowingMenu = false }
        let corner = NSPoint(x: contentView.bounds.maxX - 220, y: 44)
        // Blocks until the menu closes; the handler is retained by the items until then.
        menu.popUp(positioning: nil, at: corner, in: contentView)
        withExtendedLifetime(handler) {}
    }

    public func show() {
        window.setFrame(Self.frame(for: window.frame.size, on: Self.screenWithMouse()), display: false)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    public func hide() {
        guard window.isVisible else { return }
        window.orderOut(nil)
        lastHide = .now
        onHide?()
    }

    public func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: - Placement

    static func screenWithMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }

    /// Centered horizontally, with its top a fifth of the way down the visible area, like Spotlight.
    static func frame(for size: NSSize, on screen: NSScreen?) -> NSRect {
        guard let visible = screen?.visibleFrame else { return NSRect(origin: .zero, size: size) }
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let x = visible.midX - width / 2
        let y = visible.maxY - visible.height * 0.2 - height
        return NSRect(x: x.rounded(), y: max(visible.minY, y).rounded(), width: width, height: height)
    }
}

/// Receives the chosen menu item and hands its command back.
@MainActor
private final class MenuHandler: NSObject {
    let perform: (PanelCommand) -> Void

    init(perform: @escaping (PanelCommand) -> Void) {
        self.perform = perform
    }

    @objc func chosen(_ item: NSMenuItem) {
        guard let command = item.representedObject as? PanelCommand else { return }
        perform(command)
    }
}
