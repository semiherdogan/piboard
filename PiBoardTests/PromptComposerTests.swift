import Testing
@testable import PiBoard

struct PromptComposerTests {
    @Test func planFirstOffReturnsPromptUnchanged() {
        let result = PromptComposer.compose(prompt: "Fix the bug", planFirst: false, suffix: "Plan first.")
        #expect(result == "Fix the bug")
    }

    @Test func planFirstOnAppendsSuffixWithBlankLine() {
        let result = PromptComposer.compose(prompt: "Fix the bug", planFirst: true, suffix: "Plan first.")
        #expect(result == "Fix the bug\n\nPlan first.")
    }

    @Test func emptyPromptYieldsSuffixOnly() {
        let result = PromptComposer.compose(prompt: "", planFirst: true, suffix: "Plan first.")
        #expect(result == "Plan first.")
    }

    @Test func blankSuffixAppendsNothing() {
        let result = PromptComposer.compose(prompt: "Fix the bug", planFirst: true, suffix: "   ")
        #expect(result == "Fix the bug")
    }
}
