import CryptoKit
public import Foundation

/// The SHA-256 of a payload. Names the payload's file in the blob store.
public struct ContentHash: Hashable, Sendable, CustomStringConvertible {
    public let bytes: Data

    public init(of data: Data) {
        bytes = Data(SHA256.hash(data: data))
    }

    init(digest: SHA256.Digest) {
        bytes = Data(digest)
    }

    init?(bytes: Data) {
        guard bytes.count == SHA256.byteCount else { return nil }
        self.bytes = bytes
    }

    init?(hex: String) {
        guard hex.count == SHA256.byteCount * 2 else { return nil }
        var bytes = Data(capacity: SHA256.byteCount)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.bytes = bytes
    }

    public var hex: String { bytes.map { String(format: "%02x", $0) }.joined() }

    public var description: String { hex }
}

/// Payloads too large to keep inline in the database (over 64 KB), stored as files named by their
/// SHA-256 under `blobs/ab/abcdef…`.
///
/// Identical payloads share one file. The database decides what is referenced: callers write the
/// file before committing the row that points at it, and delete the row before removing the file.
/// A crash can therefore only leave an unreferenced file behind, which ``sweep(keeping:olderThan:)``
/// removes later. A row never points at a missing file.
public struct BlobStore: Sendable {
    /// Payloads at or below this size are stored inline in the database. SQLite reads small blobs
    /// faster inline and large ones faster from separate files; the crossover is around 100 KB.
    public static let inlineLimit = 64 << 10

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    func url(for hash: ContentHash) -> URL {
        let hex = hash.hex
        return directory.appending(path: String(hex.prefix(2)), directoryHint: .isDirectory)
            .appending(path: hex, directoryHint: .notDirectory)
    }

    /// Stores `data` and returns its hash. Writing a payload that is already stored does nothing.
    @discardableResult
    public func write(_ data: Data) throws -> ContentHash {
        let hash = ContentHash(of: data)
        let url = url(for: hash)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return hash }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Atomic: written to a temporary file and renamed, so a crash never leaves a partial payload.
        try data.write(to: url, options: .atomic)
        return hash
    }

    public func read(_ hash: ContentHash) throws -> Data {
        try Data(contentsOf: url(for: hash), options: .mappedIfSafe)
    }

    /// Removes the payload's file. Removing a payload that isn't stored is not an error.
    public func remove(_ hash: ContentHash) throws {
        do {
            try FileManager.default.removeItem(at: url(for: hash))
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    /// Deletes files that no database row references and that are older than `cutoff`, and returns
    /// how many it deleted. The age check protects files written by an ingest that hasn't committed
    /// its row yet.
    @discardableResult
    public func sweep(keeping referenced: Set<ContentHash>, olderThan cutoff: Date) throws -> Int {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard
            let files = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return 0 }
        var removed = 0
        for case let file as URL in files {
            let values = try file.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true, let modified = values.contentModificationDate, modified < cutoff
            else { continue }
            // Anything that isn't named like a blob (a stray temporary file) is also removed.
            if let hash = ContentHash(hex: file.lastPathComponent), referenced.contains(hash) { continue }
            try FileManager.default.removeItem(at: file)
            removed += 1
        }
        return removed
    }
}
