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

/// Opens the welcome window shown on first launch.
@MainActor
public final class OnboardingWindowController {
    private let settings: Settings
    private let environment: SettingsEnvironment
    private var window: NSWindow?

    public init(settings: Settings, environment: SettingsEnvironment) {
        self.settings = settings
        self.environment = environment
    }

    public func show() {
        if window == nil {
            let view = OnboardingView(settings: settings, pasteboardAccess: environment.pasteboardAccess) {
                [weak self] in
                self?.finish()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = String(localized: "Welcome to Spindle", bundle: .spindleUI, comment: "Onboarding title.")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        window?.close()
    }
}
