public import Foundation

/// Why a copy wasn't stored.
public enum SkipReason: Hashable, Sendable {
    /// The source marked it concealed, transient or auto-generated (nspasteboard.org).
    case privacyMarker
    /// It came from an app on the ignore list.
    case ignoredApp(String)
    /// It arrived through Universal Clipboard and the user doesn't keep those.
    case remoteCopy
    /// Capture is paused.
    case paused
    /// The user asked to skip this one copy.
    case skippedOnce
}

/// Decides, from the copy alone, whether Spindle may keep it.
public struct CaptureFilter: Hashable, Sendable {
    /// Password managers and Apple's credential apps. Most password managers also mark their copies
    /// as concealed, but their browser extensions can't, and Apple's Passwords menu bar extra
    /// doesn't reliably.
    public static let defaultIgnoredApps: Set<String> = [
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
    ]

    public var ignoredApps: Set<String>
    public var keepsRemoteCopies: Bool

    public init(ignoredApps: Set<String> = defaultIgnoredApps, keepsRemoteCopies: Bool = true) {
        self.ignoredApps = ignoredApps
        self.keepsRemoteCopies = keepsRemoteCopies
    }

    /// `nil` means keep it.
    public func skipReason(for copy: CapturedCopy) -> SkipReason? {
        if !copy.privacyMarkers.isEmpty { return .privacyMarker }
        if let app = ignoredSource(of: copy) { return .ignoredApp(app) }
        if copy.isRemote && !keepsRemoteCopies { return .remoteCopy }
        return nil
    }

    private func ignoredSource(of copy: CapturedCopy) -> String? {
        if let source = copy.sourceBundleID, ignoredApps.contains(source) { return source }
        // Menu bar extras never become the frontmost app, so a copy from one gets attributed to
        // whatever app was in front. Some of them declare pasteboard types prefixed with their own
        // bundle id, which gives them away.
        for app in ignoredApps where copy.declaredTypes.contains(where: { $0.rawValue.hasPrefix(app) }) {
            return app
        }
        return nil
    }
}

/// "Pause capture" and "ignore next copy", as set from the menu bar.
public struct CapturePause: Hashable, Sendable {
    public private(set) var pausedUntil: Date?
    public private(set) var skipsNextCopy = false

    public init() {}

    /// Pauses until `date`, or until ``resume()`` when `date` is `nil`.
    public mutating func pause(until date: Date?) {
        pausedUntil = date ?? .distantFuture
    }

    public mutating func resume() {
        pausedUntil = nil
    }

    public mutating func skipNextCopy() {
        skipsNextCopy = true
    }

    public func isPaused(at date: Date) -> Bool {
        guard let pausedUntil else { return false }
        return date < pausedUntil
    }

    /// Whether a copy made at `date` may be stored. Using up "ignore next copy" happens here, so call
    /// it once per copy.
    public mutating func admit(at date: Date) -> SkipReason? {
        if let pausedUntil, date >= pausedUntil {
            self.pausedUntil = nil
        }
        if isPaused(at: date) { return .paused }
        if skipsNextCopy {
            skipsNextCopy = false
            return .skippedOnce
        }
        return nil
    }
}
