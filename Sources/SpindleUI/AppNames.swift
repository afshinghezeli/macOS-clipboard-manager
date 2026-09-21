import AppKit

/// Display names of apps, looked up by bundle id through Launch Services and remembered.
@MainActor
enum AppNames {
    private static var cache: [String: String] = [:]

    /// Names for apps on the default ignore list, shown even when they aren't installed.
    private static let knownNames = [
        "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7",
        "com.bitwarden.desktop": "Bitwarden",
        "org.keepassxc.keepassxc": "KeePassXC",
    ]

    /// The app's name as Finder shows it, `stored` when that's already a real name, or the bundle
    /// id when the app isn't installed.
    static func displayName(bundleID: String?, stored: String?) -> String? {
        guard let bundleID else { return stored }
        if let stored, stored != bundleID { return stored }
        if let cached = cache[bundleID] { return cached }
        var name = knownNames[bundleID] ?? bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            if name.hasSuffix(".app") { name.removeLast(4) }
        }
        cache[bundleID] = name
        return name
    }
}
