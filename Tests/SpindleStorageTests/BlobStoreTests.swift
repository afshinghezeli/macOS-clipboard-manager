import Foundation
import Testing

@testable import SpindleStorage

@Suite
struct BlobStoreTests {
    private let store: BlobStore

    init() {
        store = BlobStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "blobs-\(UUID().uuidString)"))
    }

    private func age(_ hash: ContentHash, by interval: TimeInterval) throws {
        let date = Date.now.addingTimeInterval(-interval)
        try FileManager.default.setAttributes(
            [.modificationDate: date], ofItemAtPath: store.url(for: hash).path(percentEncoded: false))
    }

    @Test
    func roundTripsAPayload() throws {
        let payload = Data((0..<200_000).map { UInt8($0 % 251) })
        let hash = try store.write(payload)
        #expect(try store.read(hash) == payload)
    }

    @Test
    func identicalPayloadsShareOneFile() throws {
        let payload = Data(repeating: 7, count: 100_000)
        let first = try store.write(payload)
        let second = try store.write(payload)
        #expect(first == second)
        let shard = store.url(for: first).deletingLastPathComponent()
        #expect(try FileManager.default.contentsOfDirectory(atPath: shard.path(percentEncoded: false)).count == 1)
    }

    @Test
    func filesAreShardedByTheFirstTwoHexDigits() throws {
        let hash = try store.write(Data("sharded".utf8))
        let url = store.url(for: hash)
        #expect(url.lastPathComponent == hash.hex)
        #expect(url.deletingLastPathComponent().lastPathComponent == String(hash.hex.prefix(2)))
    }

    @Test
    func rewritingAnOldOrphanProtectsItFromTheSweep() throws {
        // An orphaned file from a pruned item, older than the sweep's grace period...
        let payload = Data("copied again later".utf8)
        let hash = try store.write(payload)
        try age(hash, by: 7200)
        // ...is reused by a new copy with the same content, whose row isn't committed yet.
        try store.write(payload)
        let removed = try store.sweep(keeping: [], olderThan: .now.addingTimeInterval(-3600))
        #expect(removed == 0)
        #expect(try store.read(hash) == payload)
    }

    @Test
    func removingAMissingPayloadIsNotAnError() throws {
        try store.remove(ContentHash(of: Data("never stored".utf8)))
    }

    @Test
    func sweepRemovesOnlyOldUnreferencedFiles() throws {
        let kept = try store.write(Data("referenced".utf8))
        let orphan = try store.write(Data("orphaned by a crash".utf8))
        let fresh = try store.write(Data("written a moment ago, row not committed yet".utf8))
        try age(kept, by: 7200)
        try age(orphan, by: 7200)

        let removed = try store.sweep(keeping: [kept], olderThan: .now.addingTimeInterval(-3600))

        #expect(removed == 1)
        #expect(throws: (any Error).self) { try store.read(orphan) }
        #expect(try store.read(kept) == Data("referenced".utf8))
        #expect(try store.read(fresh).isEmpty == false)
    }

    @Test
    func hashHexRoundTrips() throws {
        let hash = ContentHash(of: Data("spindle".utf8))
        #expect(hash.hex.count == 64)
        #expect(ContentHash(hex: hash.hex) == hash)
        #expect(ContentHash(hex: "zz") == nil)
    }
}
