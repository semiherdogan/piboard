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

    @Test func promptSearchTermsStartWithEachLineAsTyped() {
        #expect(SessionSummaryPresentation.promptSearchTerms("\n  fix the bug  \nrun the tests") == ["fix the bug", "run the tests"])
        let long = String(repeating: "a", count: 100)
        #expect(SessionSummaryPresentation.promptSearchTerms(long).first?.count == 40)
        #expect(SessionSummaryPresentation.promptSearchTerms(" \n ").isEmpty)
    }

    // An agent may show a pasted path as an attachment, so the words around it are the next best guess.
    @Test func promptSearchTermsTryTheLineWithoutPathsAndLinks() {
        let prompt = "'/Users/me/Library/Application Support/shot.jpg' ; echo ya izin mi versek"
        let terms = SessionSummaryPresentation.promptSearchTerms(prompt)

        #expect(terms.first == String(prompt.prefix(40)))
        #expect(terms.contains("Support/shot.jpg' ; echo ya izin mi versek") == false)
        #expect(terms.last == "echo ya izin mi versek")
        #expect(SessionSummaryPresentation.promptSearchTerms("see https://example.com/a for the spec").last == "see for the spec")
    }

    // Dropped files are quoted, and screenshot names have spaces.
    @Test func aQuotedPathWithSpacesIsDroppedAsAWhole() {
        let prompt = "'/Users/me/Desktop/Screenshot 2026-11-09 at 10.12.33.png' fix this layout"
        #expect(SessionSummaryPresentation.promptSearchTerms(prompt).last == "fix this layout")
    }

    @Test func shortPromptsAreStillSearched() {
        #expect(SessionSummaryPresentation.promptSearchTerms("devam") == ["devam"])
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
