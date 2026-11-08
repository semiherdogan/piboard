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

    @Test func stripDetailsListModelTurnsTokensAndCostWhenReported() {
        var summary = SessionSummary()
        summary.model = "claude-opus-5-5"
        summary.turnCount = 1
        summary.usage = SessionSummary.Usage(input: 1_000, output: 200, total: 1_200, cost: 0.5)

        let details = SessionSummaryPresentation.stripDetails(summary)

        #expect(details.count == 4)
        #expect(details.prefix(3) == ["claude-opus-5-5", "1 turn", "1.0k in, 200 out"])
        #expect(details.last?.contains("0.50") == true)
    }

    @Test func stripDetailsLeaveOutAMissingModelAndAZeroCost() {
        var summary = SessionSummary()
        summary.turnCount = 3

        #expect(SessionSummaryPresentation.stripDetails(summary) == ["3 turns", "0 in, 0 out"])
    }

    @Test func promptSearchTermIsTheStartOfTheFirstNonEmptyLine() {
        #expect(SessionSummaryPresentation.promptSearchTerm("\n  fix the bug  \nmore") == "fix the bug")
        let long = String(repeating: "a", count: 100)
        #expect(SessionSummaryPresentation.promptSearchTerm(long)?.count == 40)
        #expect(SessionSummaryPresentation.promptSearchTerm(" \n ") == nil)
    }

    @Test func firstLineOfLastPromptSkipsBlankLines() {
        var summary = SessionSummary()
        summary.lastUserText = "\n\nRefactor the client\nthen run tests"
        #expect(summary.firstLineOfLastPrompt == "Refactor the client")
    }

    @Test func aSessionWithoutTurnsOrRepliesHasNoStrip() {
        var summary = SessionSummary()
        #expect(SessionSummaryPresentation.hasStripContent(summary) == false)

        summary.turnCount = 1
        #expect(SessionSummaryPresentation.hasStripContent(summary))
    }
}
