public import Foundation

/// Orders search results: how well the text matches, blended with how recently and how often the
/// item was used, and whether it is pinned.
///
/// Match quality leads, the way Raycast and Alfred rank, but recency weighs almost as much because
/// clipboard searches are mostly for something copied recently. The weights live in one place so
/// the orderings in `SearchRankingTests` document their effect.
public struct SearchRanking: Hashable, Sendable {
    public struct Weights: Hashable, Sendable {
        public var quality = 1.25
        public var recency = 1.0
        public var frecency = 0.75
        public var pinned = 0.5

        public init() {}
    }

    /// What ranking needs to know about one candidate.
    public struct Candidate: Hashable, Sendable {
        /// The item's folded search text (``TextFolding/fold(_:maxUTF8Bytes:)``).
        public var text: String
        public var lastUsedAt: Date
        public var frecencyKey: Double
        public var isPinned: Bool

        public init(text: String, lastUsedAt: Date, frecencyKey: Double, isPinned: Bool) {
            self.text = text
            self.lastUsedAt = lastUsedAt
            self.frecencyKey = frecencyKey
            self.isPinned = isPinned
        }
    }

    public var weights: Weights

    /// Age at which the recency component drops to half.
    public var recencyHalfPoint: TimeInterval = 12 * 3600

    public init(weights: Weights = Weights()) {
        self.weights = weights
    }

    /// The candidate's score for `query` (already folded), or `nil` if it doesn't match.
    public func score(_ candidate: Candidate, query: String, at now: Date) -> Double? {
        guard let quality = Self.matchQuality(of: query, in: candidate.text) else { return nil }
        let age = max(0, now.timeIntervalSince(candidate.lastUsedAt))
        let recency = 1 / (1 + age / recencyHalfPoint)
        // 1 use ≈ 0.22, 4 uses ≈ 0.63, 10 uses ≈ 0.92, decaying with the frecency half-life.
        let frecency = 1 - exp(-Frecency.score(candidate.frecencyKey, at: now) / 4)
        return weights.quality * quality + weights.recency * recency + weights.frecency * frecency
            + (candidate.isPinned ? weights.pinned : 0)
    }

    /// How well `query` matches `text`, from 1.0 (identical) down to 0.3 (inside a word, far in),
    /// or `nil` when some word of the query doesn't occur. Both strings must already be folded.
    ///
    /// A multi-word query matches when every word occurs somewhere. If the words don't appear
    /// together as typed, the weakest word's quality counts, reduced by 20%.
    public static func matchQuality(of query: String, in text: String) -> Double? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        if let whole = occurrenceQuality(of: query, in: text) { return whole }

        let words = query.split(separator: " ")
        guard words.count > 1 else { return nil }
        var weakest = 1.0
        for word in words {
            guard let quality = occurrenceQuality(of: String(word), in: text) else { return nil }
            weakest = min(weakest, quality)
        }
        return weakest * 0.8
    }

    /// Characters into the text after which a match counts as "further in".
    private static let earlyLimit = 64
    /// Occurrences examined per word; enough to find a word start in any realistic text.
    private static let occurrenceLimit = 16

    private static func occurrenceQuality(of needle: String, in text: String) -> Double? {
        if text == needle { return 1.0 }
        if text.hasPrefix(needle) { return 0.8 }

        var best: Double?
        var searchStart = text.startIndex
        for _ in 0..<occurrenceLimit {
            guard let range = text.range(of: needle, range: searchStart..<text.endIndex) else { break }
            let early = text.distance(from: text.startIndex, to: range.lowerBound) < earlyLimit
            let atWordStart =
                range.lowerBound == text.startIndex || !isWordCharacter(text[text.index(before: range.lowerBound)])
            let quality: Double =
                switch (atWordStart, early) {
                case (true, true): 0.65
                case (true, false): 0.5
                case (false, true): 0.4
                case (false, false): 0.3
                }
            best = max(best ?? 0, quality)
            if quality == 0.65 { break }
            searchStart = text.index(after: range.lowerBound)
        }
        return best
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
