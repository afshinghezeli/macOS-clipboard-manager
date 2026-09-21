import Foundation

private final class BundleFinder {}

extension Bundle {
    /// The resources of the SpindleUI module.
    ///
    /// Use this instead of SwiftPM's generated `Bundle.module`. That accessor only looks next to the
    /// executable and then at an absolute path on the build machine, so inside a signed `Spindle.app`,
    /// where the bundle sits in `Contents/Resources`, it crashes on every Mac except the one that built it.
    static let spindleUI: Bundle = {
        let name = "Spindle_SpindleUI.bundle"
        let candidates = [
            // Spindle.app/Contents/Resources, where Scripts/bundle.sh puts it.
            Bundle.main.resourceURL,
            // `swift run`: next to the executable.
            Bundle.main.bundleURL,
            // `swift test`: next to the test bundle.
            Bundle(for: BundleFinder.self).bundleURL.deletingLastPathComponent(),
        ]
        for case let directory? in candidates {
            if let bundle = Bundle(url: directory.appendingPathComponent(name)) {
                return bundle
            }
        }
        preconditionFailure("\(name) is missing. Scripts/bundle.sh should copy it into Contents/Resources.")
    }()
}
