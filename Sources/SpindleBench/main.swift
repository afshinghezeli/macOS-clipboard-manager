// Measures Spindle's storage and search against generated histories, in a release build:
//
//     make bench
//
// The numbers in docs/performance.md come from here. Histories are generated from a fixed seed,
// so runs are comparable between commits and machines.

import Foundation
import SpindleCore
import SpindleStorage

/// A small, deterministic pseudo-random generator (SplitMix64), so every run builds the same history.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

let vocabulary = [
    "invoice", "meeting", "notes", "https://github.com/", "status", "deploy", "clipboard", "東京タワー", "Crème brûlée",
    "password reset", "git rebase -i", "SELECT * FROM", "quarterly report", "https://swift.org/", "#FF9500",
    "let value =", "the quick brown fox", "budget", "Mon rendez-vous", "カレンダー", "func search(", "README", "error:",
]

/// The texts of a generated history, oldest first. The same count always gives the same texts.
func historyTexts(count: Int) -> [String] {
    var random = SeededGenerator(seed: 42)
    return (0..<count).map { index in
        var words: [String] = []
        for _ in 0..<Int.random(in: 3...14, using: &random) {
            words.append(vocabulary.randomElement(using: &random)!)
        }
        words.append("#\(index)")
        return words.joined(separator: " ")
    }
}

/// Builds a history of `texts` straight into the database, the way ingest would store them.
func makeHistory(_ texts: [String], in database: AppDatabase) async throws {
    let blobs = BlobStore(
        directory: FileManager.default.temporaryDirectory.appending(path: "bench-blobs-\(texts.count)"))
    let ingestor = Ingestor(database: database, blobs: blobs)
    let start = Date(timeIntervalSince1970: 1_780_000_000)
    for (index, text) in texts.enumerated() {
        let item = CapturedItem(representations: [Representation(flavor: .plainText, data: Data(text.utf8))])
        try await ingestor.ingest(
            CapturedCopy(
                items: [item], declaredTypes: [.plainText], sourceBundleID: "com.apple.Safari", changeCount: index,
                capturedAt: start.addingTimeInterval(Double(index) * 30)))
    }
}

struct Stats {
    var samples: [Duration]
    func percentile(_ p: Double) -> Double {
        let sorted = samples.sorted()
        let index = min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.up)) - 1)
        let d = sorted[max(0, index)]
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
    var line: String {
        String(
            format: "p50 %6.2f ms   p95 %6.2f ms   p99 %6.2f ms", percentile(0.5), percentile(0.95), percentile(0.99))
    }
}

func measure(_ runs: Int, _ body: () async throws -> Void) async rethrows -> Stats {
    try await body()  // warm up
    var samples: [Duration] = []
    for _ in 0..<runs {
        let start = ContinuousClock.now
        try await body()
        samples.append(ContinuousClock.now - start)
    }
    return Stats(samples: samples)
}

let queries = ["inv", "invoice", "meeting notes", "東京", "git reb", "a", "zzqx", "https", "#123", "brûlée"]

for count in [10_000, 100_000] {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "spindle-bench-\(count)-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = try AppDatabase.open(at: StorageLocation(directory: directory))

    let texts = historyTexts(count: count)
    let buildStart = ContinuousClock.now
    try await makeHistory(texts, in: database)
    let buildTime = ContinuousClock.now - buildStart
    print(
        "\n\(count) items (built in \(buildTime.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))))"
    )

    let engine = SearchEngine(database: database)
    var all: [Duration] = []
    for query in queries {
        let stats = try await measure(30) { _ = try await engine.search(query) }
        all += stats.samples
        print("  search \(query.padding(toLength: 14, withPad: " ", startingAt: 0)) \(stats.line)")
    }
    print("  search, all queries   \(Stats(samples: all).line)")

    let history = HistoryStore(database: database, blobs: BlobStore(directory: directory.appending(path: "blobs")))
    let paging = try await measure(50) { _ = try await history.recent(limit: 100) }
    print("  first page (100)      \(paging.line)")
    let deep = try await history.recent(before: Int64(count / 2), limit: 1).first?.seq
    let deepPaging = try await measure(50) { _ = try await history.recent(before: deep, limit: 100) }
    print("  page mid-history      \(deepPaging.line)")

    let ingestor = Ingestor(database: database, blobs: BlobStore(directory: directory.appending(path: "blobs")))
    var serial = 0
    let ingest = try await measure(200) {
        serial += 1
        let item = CapturedItem(representations: [
            Representation(flavor: .plainText, data: Data("new copy \(serial) \(count)".utf8))
        ])
        try await ingestor.ingest(
            CapturedCopy(
                items: [item], declaredTypes: [.plainText], sourceBundleID: nil, changeCount: 0, capturedAt: .now))
    }
    print("  ingest one text copy  \(ingest.line)")

    // Copying something from long ago again moves it to the top, which rewrites its index entry.
    var old = 0
    let bump = try await measure(200) {
        old += 1
        let item = CapturedItem(representations: [
            Representation(flavor: .plainText, data: Data(texts[old * count / 250].utf8))
        ])
        try await ingestor.ingest(
            CapturedCopy(
                items: [item], declaredTypes: [.plainText], sourceBundleID: nil, changeCount: 0, capturedAt: .now))
    }
    print("  copy an old item again \(bump.line)")
}
