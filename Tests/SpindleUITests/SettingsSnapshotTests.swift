import AppKit
import Foundation
import SpindleCore
import SpindleSystem
import SwiftUI
import Testing

@testable import SpindleUI

@MainActor
@Suite
struct SettingsSnapshotTests {
    @Test
    func everyTab() throws {
        guard Snapshot.directory != nil else { return }
        let suite = "spindle-snapshot-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        let size = NSSize(width: 560, height: 520)
        let updates = UpdateControls(automaticallyChecks: { true }, setAutomaticallyChecks: { _ in }, checkNow: {})
        try Snapshot.write(
            GeneralSettings(settings: settings, updates: updates), named: "settings-general",
            size: NSSize(width: 560, height: 640))
        try Snapshot.write(HistorySettings(settings: settings, clearHistory: {}), named: "settings-history", size: size)
        try Snapshot.write(
            PrivacySettings(settings: settings, pasteboardAccess: { .allowed }), named: "settings-privacy", size: size)
    }
}

@MainActor
@Suite
struct OnboardingSnapshotTests {
    @Test
    func welcomeWindow() throws {
        guard Snapshot.directory != nil else { return }
        let suite = "spindle-onboarding-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try Snapshot.write(
            OnboardingView(settings: Settings(defaults: defaults), pasteboardAccess: { .allowed }, done: {}),
            named: "onboarding", size: NSSize(width: 540, height: 600))
    }
}

@MainActor
@Suite
struct MenuBarIconSnapshotTests {
    @Test
    func iconWithAndWithoutTheUpdateDot() throws {
        guard Snapshot.directory != nil else { return }
        let plain = try #require(StatusItemController.icon(withDot: false))
        let dotted = try #require(StatusItemController.icon(withDot: true))
        try Snapshot.write(
            HStack(spacing: 12) {
                Image(nsImage: plain)
                Image(nsImage: dotted)
            }
            .padding(8)
            .scaleEffect(4),
            named: "menubar-icon", size: NSSize(width: 360, height: 160))
    }
}
