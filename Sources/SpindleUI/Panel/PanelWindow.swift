import AppKit

/// The floating window the history lives in.
///
/// A non-activating panel: it takes keyboard focus without making Spindle the active app, so the
/// app you were using stays frontmost and a synthetic ⌘V lands there. `.nonactivatingPanel` must be
/// part of the style mask at initialization; adding it later leaves a panel that looks focused but
/// never receives key events.
final class PanelWindow: NSPanel {
    static let defaultSize = NSSize(width: 760, height: 460)

    /// Called when the panel loses keyboard focus, for example when the user clicks elsewhere.
    var onResignKey: (() -> Void)?
    /// Called for Esc when nothing inside the panel handled it.
    var onCancel: (() -> Void)?
    /// Offered every ⌘ shortcut before the main menu sees it. Returns whether it was used.
    var onKeyEquivalent: ((NSEvent) -> Bool)?

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true)
        isFloatingPanel = true
        level = .floating
        // Follow the user to the current Space, float over full-screen apps, stay out of Mission
        // Control and the window cycle.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
