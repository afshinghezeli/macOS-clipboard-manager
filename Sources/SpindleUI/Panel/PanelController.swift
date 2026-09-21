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
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        // The panel never makes Spindle the active app, and the default `.followsWindowActiveState`
        // would then render it flat.
        background.state = .active

        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        window = PanelWindow(contentView: background)
        window.onResignKey = { [weak self] in
            guard let self, self.window.attachedSheet == nil else { return }
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

    public var isVisible: Bool { window.isVisible }

    public func show() {
        window.setFrame(Self.frame(for: window.frame.size, on: Self.screenWithMouse()), display: false)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    public func hide() {
        guard window.isVisible else { return }
        window.orderOut(nil)
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
