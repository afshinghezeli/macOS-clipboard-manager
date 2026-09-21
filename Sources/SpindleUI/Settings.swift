public import Foundation
public import Observation
public import SpindleCore

/// The user's preferences, saved in `UserDefaults` as they change.
///
/// Structured values are stored as JSON, so a setting added or changed in a later version decodes
/// to its default instead of crashing on an old value.
@MainActor
@Observable
public final class Settings {
    public var openShortcut: KeyboardShortcut {
        didSet { save(openShortcut, as: Key.openShortcut) }
    }
    /// A global shortcut for "Ignore Next Copy"; none by default.
    public var ignoreNextCopyShortcut: KeyboardShortcut? {
        didSet { save(ignoreNextCopyShortcut, as: Key.ignoreNextCopyShortcut) }
    }
    public var retention: RetentionPolicy {
        didSet { save(retention, as: Key.retention) }
    }
    public var ignoredApps: Set<String> {
        didSet { save(ignoredApps.sorted(), as: Key.ignoredApps) }
    }
    /// Keep copies that arrive from an iPhone or another Mac through Universal Clipboard.
    public var keepsRemoteCopies: Bool {
        didSet { defaults.set(keepsRemoteCopies, forKey: Key.keepsRemoteCopies) }
    }
    /// Return pastes plain text, and ⇧Return pastes with formatting.
    public var prefersPlainText: Bool {
        didSet { defaults.set(prefersPlainText, forKey: Key.prefersPlainText) }
    }
    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboardingCompleted) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openShortcut = Self.load(KeyboardShortcut.self, Key.openShortcut, from: defaults) ?? .openPanelDefault
        ignoreNextCopyShortcut = Self.load(KeyboardShortcut?.self, Key.ignoreNextCopyShortcut, from: defaults) ?? nil
        retention = Self.load(RetentionPolicy.self, Key.retention, from: defaults) ?? RetentionPolicy()
        ignoredApps =
            Self.load([String].self, Key.ignoredApps, from: defaults).map(Set.init)
            ?? CaptureFilter.defaultIgnoredApps
        keepsRemoteCopies = defaults.object(forKey: Key.keepsRemoteCopies) as? Bool ?? true
        prefersPlainText = defaults.bool(forKey: Key.prefersPlainText)
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboardingCompleted)
    }

    /// The capture filter these settings describe.
    public var captureFilter: CaptureFilter {
        CaptureFilter(ignoredApps: ignoredApps, keepsRemoteCopies: keepsRemoteCopies)
    }

    private enum Key {
        static let openShortcut = "openShortcut"
        static let ignoreNextCopyShortcut = "ignoreNextCopyShortcut"
        static let retention = "retention"
        static let ignoredApps = "ignoredApps"
        static let keepsRemoteCopies = "keepsRemoteCopies"
        static let prefersPlainText = "prefersPlainText"
        static let onboardingCompleted = "onboardingCompleted"
    }

    private func save(_ value: some Encodable, as key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, _ key: String, from defaults: UserDefaults) -> Value?
    {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
