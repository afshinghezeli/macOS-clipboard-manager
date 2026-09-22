/// Matches a query against text with typos allowed, for when a search finds little or nothing.
///
/// Each query word of four or more characters may be one edit away from a word in the text, or
/// from the start of one, since the last word is often still being typed. Eight or more characters
/// allow two edits. An edit inserts, deletes or replaces a character, or swaps two neighbors, the
/// most common typo. Shorter query words must appear as typed. Both sides are folded text.
public struct TypoMatch: Sendable {
    private let correctable: [[UInt32]]
    /// The query words too short to correct, which a matching text contains as typed.
    public let literal: [String]
    /// Columns in the edit table: the longest word prefix compared, plus one.
    private let columns: Int

    /// `nil` when no word is long enough to correct.
    public init?(query words: [String]) {
        var correctable: [[UInt32]] = []
        var literal: [String] = []
        for word in words where !word.isEmpty {
            let scalars = word.unicodeScalars.map(\.value)
            if scalars.count >= 4 {
                correctable.append(scalars)
            } else {
                literal.append(word)
            }
        }
        guard !correctable.isEmpty else { return nil }
        self.correctable = correctable
        self.literal = literal
        columns = correctable.map { $0.count + Self.allowedEdits(forLength: $0.count) }.max()! + 1
    }

    static func allowedEdits(forLength length: Int) -> Int { length >= 8 ? 2 : 1 }

    /// The fewest edits that make every query word match, added up, or `nil` if one can't.
    public func edits(in text: String) -> Int? {
        for word in literal where !text.contains(word) { return nil }
        let scalars = text.unicodeScalars.map(\.value)
        // One allocation per text: the best distance per query word, then three table rows.
        return withUnsafeTemporaryAllocation(of: Int.self, capacity: correctable.count + 3 * columns) { buffer in
            let best = UnsafeMutableBufferPointer(rebasing: buffer[0..<correctable.count])
            for (index, query) in correctable.enumerated() {
                best[index] = Self.allowedEdits(forLength: query.count) + 1
            }
            var table = EditTable(storage: UnsafeMutableBufferPointer(rebasing: buffer[correctable.count...]))

            var start: Int?
            for index in 0...scalars.count {
                if index < scalars.count, Self.isWordCharacter(scalars[index]) {
                    if start == nil { start = index }
                    continue
                }
                guard let first = start else { continue }
                start = nil
                let word = scalars[first..<index]
                for (queryIndex, query) in correctable.enumerated() where best[queryIndex] > 0 {
                    let allowed = Self.allowedEdits(forLength: query.count)
                    guard word.count >= query.count - allowed else { continue }
                    best[queryIndex] = min(
                        best[queryIndex], table.distance(from: query, toStartOf: word, allowed: allowed))
                }
            }

            var total = 0
            for (index, query) in correctable.enumerated() {
                guard best[index] <= Self.allowedEdits(forLength: query.count) else { return nil }
                total += best[index]
            }
            return total
        }
    }

    private static func isWordCharacter(_ value: UInt32) -> Bool {
        if value < 0x80 {
            return (0x61...0x7A).contains(value) || (0x30...0x39).contains(value) || (0x41...0x5A).contains(value)
        }
        guard let scalar = Unicode.Scalar(value) else { return false }
        return scalar.properties.isAlphabetic || scalar.properties.generalCategory == .decimalNumber
    }
}

/// Three rows of the edit-distance table, in memory the caller owns.
private struct EditTable {
    private var previous: UnsafeMutableBufferPointer<Int>
    private var current: UnsafeMutableBufferPointer<Int>
    private var next: UnsafeMutableBufferPointer<Int>

    init(storage: UnsafeMutableBufferPointer<Int>) {
        let width = storage.count / 3
        previous = UnsafeMutableBufferPointer(rebasing: storage[0..<width])
        current = UnsafeMutableBufferPointer(rebasing: storage[width..<2 * width])
        next = UnsafeMutableBufferPointer(rebasing: storage[2 * width..<3 * width])
    }

    /// The smallest optimal-string-alignment distance from `query` to `word` or one of its
    /// prefixes at least `query.count - allowed` long, capped at `allowed + 1`.
    mutating func distance(from query: [UInt32], toStartOf word: ArraySlice<UInt32>, allowed: Int) -> Int {
        let limit = allowed + 1
        let base = word.startIndex
        let columns = min(word.count, query.count + allowed) + 1
        // Row i holds the distances from query[..<i] to each prefix word[..<j].
        for j in 0..<columns { current[j] = j }
        for i in 1...query.count {
            next[0] = i
            var rowMinimum = i
            for j in 1..<columns {
                let cost = query[i - 1] == word[base + j - 1] ? 0 : 1
                var value = min(current[j] + 1, next[j - 1] + 1, current[j - 1] + cost)
                if i > 1, j > 1, query[i - 1] == word[base + j - 2], query[i - 2] == word[base + j - 1] {
                    value = min(value, previous[j - 2] + 1)  // two neighbors swapped
                }
                next[j] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum >= limit { return limit }
            (previous, current, next) = (current, next, previous)
        }
        // The last row: the whole query against each prefix long enough to count.
        var best = limit
        for j in max(query.count - allowed, 0)..<columns { best = min(best, current[j]) }
        return best
    }
}
