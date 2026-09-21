import Foundation
import Testing

@testable import SpindleCore

@Suite
struct MatchQualityTests {
    private func quality(_ query: String, _ text: String) -> Double? {
        SearchRanking.matchQuality(of: query, in: text)
    }

    @Test
    func exactTextIsTheBestMatch() {
        #expect(quality("git status", "git status") == 1.0)
    }

    @Test
    func prefixComesNext() {
        #expect(quality("git", "git status") == 0.8)
    }

    @Test
    func aWordStartNearTheBeginningBeatsOneFurtherIn() {
        #expect(quality("status", "git status") == 0.65)
        let late = String(repeating: "x", count: 80) + " status"
        #expect(quality("status", late) == 0.5)
    }

    @Test
    func aMatchInsideAWordIsWeakest() {
        #expect(quality("board", "clipboard") == 0.4)
        let late = String(repeating: "x", count: 80) + " clipboard"
        #expect(quality("board", late) == 0.3)
    }

    @Test
    func theBestOccurrenceCounts() {
        #expect(quality("board", "clipboard board") == 0.65)
    }

    @Test
    func wordsCanMatchOutOfOrder() throws {
        // "git" is a prefix (0.8), "status" a word start (0.65); out-of-order matches cost 20%.
        let score = try #require(quality("status git", "git status"))
        #expect(abs(score - 0.65 * 0.8) < 1e-9)
    }

    @Test
    func everyWordMustMatch() {
        #expect(quality("git rebase", "git status") == nil)
        #expect(quality("zebra", "git status") == nil)
    }

    @Test
    func anEmptyQueryMatchesNothing() {
        #expect(quality("", "git status") == nil)
        #expect(quality("   ", "git status") == nil)
    }
}

@Suite
struct SearchRankingTests {
    private let ranking = SearchRanking()
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let hour: TimeInterval = 3600

    private func score(
        _ query: String, _ text: String, age: TimeInterval = 0, uses: Int = 1, pinned: Bool = false
    ) -> Double {
        let usedAt = now.addingTimeInterval(-age)
        var key = Frecency.key(firstUsedAt: usedAt)
        for _ in 1..<uses { key = Frecency.key(key, usedAgainAt: usedAt) }
        let candidate = SearchRanking.Candidate(text: text, lastUsedAt: usedAt, frecencyKey: key, isPinned: pinned)
        return ranking.score(candidate, query: query, at: now) ?? -.infinity
    }

    @Test
    func atTheSameAgeBetterMatchesRankHigher() {
        let exact = score("invoice", "invoice")
        let prefix = score("invoice", "invoice 2026-09.pdf")
        let wordStart = score("invoice", "paid invoice")
        let insideWord = score("voice", "invoice")
        #expect(exact > prefix)
        #expect(prefix > wordStart)
        #expect(wordStart > insideWord)
    }

    @Test
    func atTheSameQualityNewerRanksHigher() {
        #expect(score("status", "git status", age: 60) > score("status", "git status", age: 5 * hour))
    }

    @Test
    func pinnedRanksAboveUnpinned() {
        #expect(score("status", "git status", pinned: true) > score("status", "git status"))
    }

    @Test
    func anExactMatchFromYesterdayBeatsAWeakMatchFromNow() {
        #expect(score("voice", "voice", age: 24 * hour) > score("voice", "invoice", age: 60))
    }

    @Test
    func afterAWeekRecencyWinsUnlessTheOldItemIsPinnedOrUsedOften() {
        let weekOld = 7 * 24 * hour
        let fresh = score("voice", "invoice", age: 60)
        #expect(score("voice", "voice", age: weekOld) < fresh)
        #expect(score("voice", "voice", age: weekOld, pinned: true) > fresh)
        // Something pasted all the time, like an email address. Ten uses a week ago aren't quite
        // enough to beat a fresh weak match; twenty are.
        #expect(score("voice", "voice", age: weekOld, uses: 10) < fresh)
        #expect(score("voice", "voice", age: weekOld, uses: 20) > fresh)
    }

    @Test
    func nonMatchesHaveNoScore() {
        let candidate = SearchRanking.Candidate(
            text: "git status", lastUsedAt: now, frecencyKey: Frecency.key(firstUsedAt: now), isPinned: false)
        #expect(ranking.score(candidate, query: "zebra", at: now) == nil)
    }
}
