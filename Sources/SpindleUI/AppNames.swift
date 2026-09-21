import AppKit

/// Display names of apps, looked up by bundle id through Launch Services and remembered.
@MainActor
enum AppNames {
    private static var cache: [String: String] = [:]

    /// The app's name as Finder shows it, `stored` when that's already a real name, or the bundle
    /// id when the app isn't installed.
    static func displayName(bundleID: String?, stored: String?) -> String? {
        guard let bundleID else { return stored }
        if let stored, stored != bundleID { return stored }
        if let cached = cache[bundleID] { return cached }
        var name = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            if name.hasSuffix(".app") { name.removeLast(4) }
        }
        cache[bundleID] = name
        return name
    }
}
