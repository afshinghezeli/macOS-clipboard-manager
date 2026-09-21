import AppKit
import SwiftUI

/// Opens the settings window, creating it the first time.
@MainActor
public final class SettingsWindowController {
    private let settings: Settings
    private let environment: SettingsEnvironment
    private var window: NSWindow?

    public init(settings: Settings, environment: SettingsEnvironment) {
        self.settings = settings
        self.environment = environment
    }

    public func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, environment: environment))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Spindle Settings", bundle: .spindleUI, comment: "Settings window title.")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // An agent app has to activate itself for its window to take keyboard focus.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
