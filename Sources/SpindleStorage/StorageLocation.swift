public import Foundation

/// Where Spindle keeps its data on disk.
///
/// In the sandboxed app, Application Support resolves inside the app's container:
/// `~/Library/Containers/<bundle id>/Data/Library/Application Support/Spindle`.
public struct StorageLocation: Sendable, Equatable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func applicationSupport() throws -> StorageLocation {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return StorageLocation(directory: base.appending(path: "Spindle", directoryHint: .isDirectory))
    }

    public var databaseURL: URL { directory.appending(path: "history.sqlite", directoryHint: .notDirectory) }

    /// Payloads over 64 KB, stored as files named by their SHA-256 (see `BlobStore`).
    public var blobsDirectory: URL { directory.appending(path: "blobs", directoryHint: .isDirectory) }
}
