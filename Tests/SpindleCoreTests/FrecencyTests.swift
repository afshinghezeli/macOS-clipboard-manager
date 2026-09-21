import Foundation
import Testing

@testable import SpindleCore

@Suite
struct FrecencyTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    @Test
    func aSingleUseScoresOne() {
        let key = Frecency.key(firstUsedAt: start)
        #expect(abs(Frecency.score(key, at: start) - 1) < 1e-9)
    }

    @Test
    func scoreHalvesEveryHalfLife() {
        let key = Frecency.key(firstUsedAt: start)
        let later = start.addingTimeInterval(Frecency.halfLife)
        #expect(abs(Frecency.score(key, at: later) - 0.5) < 1e-9)
        #expect(abs(Frecency.score(key, at: later.addingTimeInterval(Frecency.halfLife)) - 0.25) < 1e-9)
    }

    @Test
    func eachUseAddsOne() {
        var key = Frecency.key(firstUsedAt: start)
        key = Frecency.key(key, usedAgainAt: start)
        key = Frecency.key(key, usedAgainAt: start)
        #expect(abs(Frecency.score(key, at: start) - 3) < 1e-9)
    }

    @Test
    func frequentOldUseCanOutrankOneRecentUse() {
        var often = Frecency.key(firstUsedAt: start)
        for _ in 0..<9 { often = Frecency.key(often, usedAgainAt: start) }
        let once = Frecency.key(firstUsedAt: start.addingTimeInterval(Frecency.halfLife))
        // Ten uses one half-life ago are worth five now; one use now is worth one.
        #expect(often > once)
    }

    @Test
    func keysOrderLikeScoresAtAnyMoment() {
        let a = Frecency.key(firstUsedAt: start)
        let b = Frecency.key(Frecency.key(firstUsedAt: start.addingTimeInterval(-86_400)), usedAgainAt: start)
        for offset in stride(from: 0.0, through: 30 * 86_400, by: 86_400) {
            let moment = start.addingTimeInterval(offset)
            #expect((a < b) == (Frecency.score(a, at: moment) < Frecency.score(b, at: moment)))
        }
    }

    @Test
    func keysStayPreciseFarInTheFuture() {
        let future = Date(timeIntervalSince1970: 4_000_000_000)  // 2096
        let key = Frecency.key(Frecency.key(firstUsedAt: future), usedAgainAt: future)
        #expect(abs(Frecency.score(key, at: future) - 2) < 1e-6)
    }
}
