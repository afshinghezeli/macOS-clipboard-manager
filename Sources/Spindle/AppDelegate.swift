import AppKit
import SpindleCore
import SpindleStorage
import SpindleSystem
import SpindleUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Diagnostics.subsystem, category: "App")
    private var statusItemController: StatusItemController?
    private var capture: CaptureController?
    private var maintenance: Maintenance?
    private var openShortcut = KeyboardShortcut.openPanelDefault
    /// The app that was in front when the panel opened; pasting goes there.
    private var pasteTarget: NSRunningApplication?
    private var panelModel = PanelModel()
    private var panel: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["SPINDLE_SMOKE_TEST"] == "1" {
            runSmokeTest()
        }
        NSApp.mainMenu = MainMenu.make()

        do {
            let location = try StorageLocation.applicationSupport()
            let database = try AppDatabase.open(at: location)
            let blobs = BlobStore(directory: location.blobsDirectory)
            let history = HistoryStore(database: database, blobs: blobs)
            let capture = CaptureController(ingestor: Ingestor(database: database, blobs: blobs), history: history)
            capture.start(gateway: PasteboardGateway())
            self.capture = capture

            panelModel = PanelModel(history: history, search: SearchEngine(database: database))
            capture.onChange = { [weak self] change in
                guard let self, self.panel?.isVisible == true else { return }
                Task { await self.panelModel.apply(change) }
            }

            // M4.2 makes the policy a setting; until then everything is kept up to 2 GB.
            let maintenance = Maintenance(
                pruner: Pruner(database: database, blobs: blobs),
                policy: { RetentionPolicy() },
                didPrune: { [weak capture] in capture?.refreshItemCount() })
            maintenance.start()
            self.maintenance = maintenance
        } catch {
            // The menu shows "History unavailable"; M4 adds a way to recover.
            logger.fault("Opening the history failed: \(error.localizedDescription, privacy: .public)")
        }

        statusItemController = StatusItemController(
            state: { [weak self] in
                StatusMenuState(
                    itemCount: self?.capture?.itemCount, isPaused: self?.capture?.isPaused ?? false,
                    openShortcut: self?.menuShortcut)
            },
            openPanel: { [weak self] in self?.openPanel() },
            togglePause: { [weak self] in self?.capture?.togglePause() })
        // Built now, so the first open is instant.
        let panel = PanelController(rootView: PanelView(model: panelModel))
        panel.onCommand = { [weak self] in self?.panelModel.handle($0) ?? false }
        panelModel.onClose = { [weak panel] in panel?.hide() }
        self.panel = panel
        registerShortcut()
        #if DEBUG
        // `open --env SPINDLE_OPEN_PANEL=1 dist/debug/Spindle.app` opens the panel at launch, for
        // checking it without a shortcut or a click.
        if ProcessInfo.processInfo.environment["SPINDLE_OPEN_PANEL"] == "1" { openPanel() }
        #endif
        logger.notice("Launched")
    }

    private func registerShortcut() {
        do {
            _ = try HotKeyCenter.shared.register(openShortcut) { [weak self] in self?.shortcutPressed() }
        } catch {
            // M4.5 tells the user and offers to pick another one.
            logger.error("Registering the shortcut failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func shortcutPressed() {
        if panel?.isVisible == true {
            panel?.hide()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            pasteTarget = frontmost
        }
        panelModel.panelWillOpen()
        panel?.show()
    }

    private var menuShortcut: (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard let key = KeyboardLayout.character(forKeyCode: openShortcut.keyCode) else { return nil }
        var flags: NSEvent.ModifierFlags = []
        if openShortcut.modifiers.contains(.control) { flags.insert(.control) }
        if openShortcut.modifiers.contains(.option) { flags.insert(.option) }
        if openShortcut.modifiers.contains(.shift) { flags.insert(.shift) }
        if openShortcut.modifiers.contains(.command) { flags.insert(.command) }
        return (key, flags)
    }

    /// See `Scripts/verify-bundle.sh`.
    private func runSmokeTest() -> Never {
        let passed = ResourceCheck.run()
        print(passed ? "SMOKE_OK" : "SMOKE_FAILED: resources not found")
        exit(passed ? 0 : 1)
    }
}
