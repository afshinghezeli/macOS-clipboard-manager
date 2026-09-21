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
    private var pasteService: PasteService?
    private var settingsWindow: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var gateway: PasteboardGateway?
    private var pruner: Pruner?
    private let settings = Settings()
    private var shortcutRegistration: UInt32?
    private var ignoreShortcutRegistration: UInt32?
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
            // One gateway for reading and writing, so a paste from history is recognized as
            // Spindle's own write and not captured again.
            let gateway = PasteboardGateway()
            let capture = CaptureController(ingestor: Ingestor(database: database, blobs: blobs), history: history)
            capture.filter = { [settings] in settings.captureFilter }
            capture.start(gateway: gateway)
            self.capture = capture
            pasteService = PasteService(history: history, gateway: gateway)
            self.gateway = gateway
            let pruner = Pruner(database: database, blobs: blobs)
            self.pruner = pruner

            panelModel = PanelModel(history: history, search: SearchEngine(database: database))
            capture.onChange = { [weak self] change in
                guard let self, self.panel?.isVisible == true else { return }
                Task { await self.panelModel.apply(change) }
            }

            let maintenance = Maintenance(
                pruner: pruner,
                policy: { [settings] in settings.retention },
                didPrune: { [weak capture] in capture?.refreshItemCount() })
            maintenance.start()
            self.maintenance = maintenance
        } catch {
            // The menu shows "History unavailable"; M4 adds a way to recover.
            logger.fault("Opening the history failed: \(error.localizedDescription, privacy: .public)")
        }

        statusItemController = StatusItemController(
            state: { [weak self] in
                var state = StatusMenuState(
                    itemCount: self?.capture?.itemCount, isPaused: self?.capture?.isPaused ?? false,
                    pausedUntil: self?.capture?.pausedUntil,
                    isSkippingNextCopy: self?.capture?.isSkippingNextCopy ?? false, openShortcut: self?.menuShortcut)
                state.isClipboardBlocked = self?.capture?.restriction != nil
                return state
            },
            actions: StatusMenuActions(
                togglePanel: { [weak self] in
                    guard let self, self.panel?.didJustHide != true else { return }
                    self.shortcutPressed()
                },
                pause: { [weak self] in self?.capture?.pause(for: $0) },
                resume: { [weak self] in self?.capture?.resume() },
                skipNextCopy: { [weak self] in self?.capture?.skipNextCopy() },
                openSettings: { [weak self] in self?.openSettings() }))
        let environment = SettingsEnvironment(
            pasteboardAccess: { [weak self] in self?.gateway?.currentAccess ?? .allowed },
            clearHistory: { [weak self] in await self?.clearHistory() })
        settingsWindow = SettingsWindowController(settings: settings, environment: environment)
        if !settings.hasCompletedOnboarding {
            let onboarding = OnboardingWindowController(settings: settings, environment: environment)
            onboarding.show()
            self.onboarding = onboarding
        }
        // Built now, so the first open is instant.
        let panel = PanelController(rootView: PanelView(model: panelModel))
        panel.onCommand = { [weak self] in self?.panelModel.handle($0) ?? false }
        panelModel.onClose = { [weak panel] in panel?.hide() }
        panelModel.onShowActions = { [weak self, weak panel] in
            guard let self, let item = self.panelModel.selectedItem else { return }
            let actions = PanelActions.list(
                for: item, targetAppName: self.panelModel.targetAppName, canPaste: self.panelModel.canPaste)
            panel?.showActionsMenu(actions) { [weak self] in self?.panelModel.handle($0) }
        }
        panelModel.onPaste = { [weak self] item, mode in
            guard let self, let pasteService = self.pasteService else { return }
            let target = self.pasteTarget
            // With "paste as plain text by default", Return and ⇧Return trade places.
            let mode: PasteMode =
                switch (mode, self.settings.prefersPlainText) {
                case (.paste, true): .pasteAsPlainText
                case (.pasteAsPlainText, true): .paste
                default: mode
                }
            Task { await pasteService.perform(item, mode: mode, into: target, hidePanel: { panel.hide() }) }
        }
        self.panel = panel
        registerShortcut()
        #if DEBUG
        // `open --env SPINDLE_OPEN_PANEL=1 dist/debug/Spindle.app` opens the panel at launch, for
        // checking it without a shortcut or a click.
        if ProcessInfo.processInfo.environment["SPINDLE_OPEN_PANEL"] == "1" { openPanel() }
        #endif
        logger.notice("Launched")
    }

    @objc func openSettings() {
        panel?.hide()
        settingsWindow?.show()
    }

    private func clearHistory() async {
        do {
            let removed = try await pruner?.clearHistory() ?? 0
            logger.notice("Cleared the history: \(removed) items removed")
        } catch {
            logger.error("Clearing the history failed: \(error.localizedDescription, privacy: .public)")
        }
        capture?.refreshItemCount()
        await panelModel.reload()
    }

    /// Opening Spindle again from Finder or Spotlight shows the panel. macOS 26 can hide menu bar
    /// icons, so this may be the only way someone finds it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPanel()
        return false
    }

    /// Registers the shortcut from Settings, and again whenever it changes there.
    private func registerShortcut() {
        if let shortcutRegistration { HotKeyCenter.shared.unregister(shortcutRegistration) }
        shortcutRegistration = nil
        do {
            shortcutRegistration = try HotKeyCenter.shared.register(settings.openShortcut) { [weak self] in
                self?.shortcutPressed()
            }
        } catch {
            // M4.5 tells the user and offers to pick another one.
            logger.error("Registering the shortcut failed: \(String(describing: error), privacy: .public)")
        }
        if let ignoreShortcutRegistration { HotKeyCenter.shared.unregister(ignoreShortcutRegistration) }
        ignoreShortcutRegistration = nil
        if let shortcut = settings.ignoreNextCopyShortcut {
            ignoreShortcutRegistration = try? HotKeyCenter.shared.register(shortcut) { [weak self] in
                self?.capture?.skipNextCopy()
            }
        }
        withObservationTracking {
            _ = settings.openShortcut
            _ = settings.ignoreNextCopyShortcut
        } onChange: { [weak self] in
            Task { @MainActor in self?.registerShortcut() }
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
        panelModel.targetAppName = pasteTarget?.localizedName
        panelModel.canPaste = PasteInjector.isPermitted
        let access = gateway?.currentAccess ?? .allowed
        panelModel.clipboardAccessProblem = access == .allowed ? nil : access
        panelModel.panelWillOpen()
        panel?.show()
    }

    private var menuShortcut: (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard let key = KeyboardLayout.character(forKeyCode: settings.openShortcut.keyCode) else { return nil }
        var flags: NSEvent.ModifierFlags = []
        if settings.openShortcut.modifiers.contains(.control) { flags.insert(.control) }
        if settings.openShortcut.modifiers.contains(.option) { flags.insert(.option) }
        if settings.openShortcut.modifiers.contains(.shift) { flags.insert(.shift) }
        if settings.openShortcut.modifiers.contains(.command) { flags.insert(.command) }
        return (key, flags)
    }

    /// See `Scripts/verify-bundle.sh`.
    private func runSmokeTest() -> Never {
        let passed = ResourceCheck.run()
        print(passed ? "SMOKE_OK" : "SMOKE_FAILED: resources not found")
        exit(passed ? 0 : 1)
    }
}
