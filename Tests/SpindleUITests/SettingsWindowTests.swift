import AppKit
import SpindleSystem
import SwiftUI
import Testing

@testable import SpindleUI

@MainActor
@Suite
struct SettingsWindowTests {
    private func makeSettings() -> SpindleUI.Settings {
        SpindleUI.Settings(defaults: UserDefaults(suiteName: "settings-window-\(UUID().uuidString)")!)
    }

    private func height(of view: some View) -> CGFloat {
        let hosting = NSHostingView(rootView: view.frame(width: 520))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    /// A TabView reports no height to AppKit, so the window once opened as a 70 pt strip with
    /// empty tabs. Every tab must fit in the window the settings view asks for.
    @Test
    func theWindowOpensTallEnoughForEveryTab() {
        let settings = makeSettings()
        let updates = UpdateControls(automaticallyChecks: { true }, setAutomaticallyChecks: { _ in }, checkNow: {})
        let environment = SettingsEnvironment(
            pasteboardAccess: { .allowed }, clearHistory: {}, importFromMaccy: { _ in 0 }, updates: updates)
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, environment: environment))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [NSWindow.StyleMask.titled, .closable]
        hosting.view.layoutSubtreeIfNeeded()
        window.setContentSize(hosting.view.fittingSize)

        let tabBarAndPadding: CGFloat = 70
        let content = window.contentLayoutRect.height
        #expect(content > 400)
        for (name, tab) in [
            ("General", AnyView(GeneralSettings(settings: settings, updates: updates))),
            ("History", AnyView(HistorySettings(settings: settings, clearHistory: {}))),
            ("Privacy", AnyView(PrivacySettings(settings: settings, pasteboardAccess: { .allowed }))),
        ] {
            let needed = height(of: tab) + tabBarAndPadding
            #expect(needed <= content, "the \(name) tab needs \(needed) pt, the window is \(content) pt")
        }
    }
}
