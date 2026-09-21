import Testing

@testable import SpindleCore

@Suite
struct HistoryFilterTests {
    @Test
    func cyclesThroughEveryFilterAndBack() {
        var filter = HistoryFilter.all
        var seen: [HistoryFilter] = []
        repeat {
            seen.append(filter)
            filter = filter.next
        } while filter != .all
        #expect(seen == HistoryFilter.allCases)
    }

    @Test
    func textIncludesFormattedText() {
        #expect(HistoryFilter.text.includes(.richText))
        #expect(!HistoryFilter.text.includes(.link))
        #expect(HistoryFilter.all.includes(.color))
    }
}
