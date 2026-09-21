public import AppKit

/// Places in System Settings that Spindle sends people to.
public enum SystemSettingsPane {
    /// Privacy & Security → Accessibility, where the paste permission is granted.
    case accessibility
    /// Privacy & Security → Paste from Other Apps (macOS 15.4 and later).
    case pasteboard

    public var url: URL {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .pasteboard:
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Pasteboard")!
        }
    }

    @MainActor
    public func open() {
        NSWorkspace.shared.open(url)
    }
}
