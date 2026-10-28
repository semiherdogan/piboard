import Testing
@testable import PiBoard

struct SessionSummaryPresentationTests {
    @Test func compactUsesThresholds() {
        #expect(SessionSummaryPresentation.compact(950) == "950")
        #expect(SessionSummaryPresentation.compact(1_000) == "1.0k")
        #expect(SessionSummaryPresentation.compact(12_345) == "12.3k")
        #expect(SessionSummaryPresentation.compact(2_345_678) == "2.3M")
    }

    @Test func tokensFoldCacheIntoInput() {
        let usage = SessionSummary.Usage(input: 200, output: 1_200, cacheRead: 12_000, cacheWrite: 100, total: 13_500, cost: 0)

        #expect(SessionSummaryPresentation.tokens(usage) == "12.3k in, 1.2k out")
    }

    @Test func costShowsTheAmount() {
        #expect(SessionSummaryPresentation.cost(0.03).contains("0.03"))
    }
}
