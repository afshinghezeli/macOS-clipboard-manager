import Foundation
import SpindleCore
import Testing

@testable import SpindleUI

@MainActor
@Suite
final class SettingsTests {
    private let suite = "spindle-settings-\(UUID().uuidString)"
    private nonisolated(unsafe) let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suite)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }

    @Test
    func startsWithSensibleDefaults() {
        let settings = Settings(defaults: defaults)
        #expect(settings.openShortcut == .openPanelDefault)
        #expect(settings.retention == RetentionPolicy())
        #expect(settings.ignoredApps == CaptureFilter.defaultIgnoredApps)
        #expect(settings.keepsRemoteCopies)
        #expect(!settings.prefersPlainText)
        #expect(!settings.receivesBetaUpdates)
        #expect(!settings.hasCompletedOnboarding)
        #expect(settings.ignoreNextCopyShortcut == nil)
    }

    @Test
    func changesSurviveARelaunch() {
        let settings = Settings(defaults: defaults)
        settings.openShortcut = KeyboardShortcut(keyCode: 49, modifiers: [.option, .command])
        settings.retention = RetentionPolicy(
            maxAge: 30 * 86_400, maxTotalBytes: 1_000_000_000, maxAgeByKind: [.image: 7 * 86_400.0])
        settings.ignoredApps.insert("com.tinyspeck.slackmacgap")
        settings.keepsRemoteCopies = false
        settings.prefersPlainText = true
        settings.receivesBetaUpdates = true
        settings.hasCompletedOnboarding = true
        settings.ignoreNextCopyShortcut = KeyboardShortcut(keyCode: 34, modifiers: [.control, .option, .command])

        let reloaded = Settings(defaults: defaults)
        #expect(reloaded.openShortcut == settings.openShortcut)
        #expect(reloaded.retention == settings.retention)
        #expect(reloaded.ignoredApps.contains("com.tinyspeck.slackmacgap"))
        #expect(!reloaded.keepsRemoteCopies)
        #expect(reloaded.prefersPlainText)
        #expect(reloaded.receivesBetaUpdates)
        #expect(reloaded.hasCompletedOnboarding)
        #expect(reloaded.ignoreNextCopyShortcut == settings.ignoreNextCopyShortcut)
    }

    @Test
    func unreadableValuesFallBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: "retention")
        #expect(Settings(defaults: defaults).retention == RetentionPolicy())
    }

    @Test
    func theCaptureFilterFollowsTheSettings() {
        let settings = Settings(defaults: defaults)
        settings.keepsRemoteCopies = false
        #expect(settings.captureFilter == CaptureFilter(keepsRemoteCopies: false))
    }
}
