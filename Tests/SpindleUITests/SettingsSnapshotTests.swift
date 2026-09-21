import AppKit
import Foundation
import SpindleCore
import SpindleSystem
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
        try Snapshot.write(GeneralSettings(settings: settings), named: "settings-general", size: size)
        try Snapshot.write(HistorySettings(settings: settings, clearHistory: {}), named: "settings-history", size: size)
        try Snapshot.write(
            PrivacySettings(settings: settings, pasteboardAccess: { .allowed }), named: "settings-privacy", size: size)
    }
}
