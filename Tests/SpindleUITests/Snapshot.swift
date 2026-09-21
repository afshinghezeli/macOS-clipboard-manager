import AppKit
import SwiftUI

/// Renders views to PNG files for looking at the UI without a screen recording, which would need a
/// permission. Only active when `SPINDLE_SNAPSHOT_DIR` is set:
///
///     SPINDLE_SNAPSHOT_DIR=/tmp/snapshots make test
@MainActor
enum Snapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["SPINDLE_SNAPSHOT_DIR"].map {
            URL(filePath: $0, directoryHint: .isDirectory)
        }
    }

    static func write(
        _ view: some View, named name: String, size: NSSize, appearance: NSAppearance.Name = .aqua
    ) throws {
        guard let directory else { return }
        let hosting = NSHostingView(
            rootView: view.frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appending(path: "\(name).png"))
    }
}
