import Testing
@testable import PiBoard

private let columns = 20

struct TerminalSoftWrapJoinerTests {
    private func join(_ text: String?, start: Int = 0) -> String {
        TerminalSoftWrapJoiner.join(text, columns: columns, firstLineStartColumn: start)
    }

    @Test func wrappedParagraphJoined() {
        #expect(join(" alpha beta gamma\n delta") == " alpha beta gamma delta")
    }

    @Test func shortLinesKept() {
        #expect(join("foo\nbar") == "foo\nbar")
    }

    @Test func listItemsNotJoined() {
        let text = "- alpha beta gamma\n- delta"
        #expect(join(text) == text)
    }

    @Test func listContinuationJoined() {
        #expect(join("- alpha beta gamma\n  delta") == "- alpha beta gamma delta")
    }

    @Test func orderedListContinuationJoined() {
        #expect(join("1. alpha beta gamma\n   delta") == "1. alpha beta gamma delta")
    }

    @Test func indentMismatchKept() {
        let text = "alpha beta gamma\n    code()"
        #expect(join(text) == text)
    }

    @Test func boxBorderKept() {
        let text = "│ alpha beta gamma │\n│ delta │"
        #expect(join(text) == text)
    }

    @Test func longTokenCutMidWordJoinsWithoutSpace() {
        #expect(join("abcdefghijklmnopqrst\nuvw") == "abcdefghijklmnopqrstuvw")
    }

    @Test func partialFirstLineUsesStartColumn() {
        #expect(join("gamma\ndelta", start: 12) == "gamma delta")
        #expect(join("gamma\ndelta") == "gamma\ndelta")
    }

    @Test func blankLineParagraphBreakKept() {
        let text = "alpha beta gamma\n\ndelta"
        #expect(join(text) == text)
    }

    @Test func headingKept() {
        let text = "alpha beta gamma\n# Title"
        #expect(join(text) == text)
    }

    @Test func nilGivesEmptyString() {
        #expect(join(nil) == "")
    }

    @Test func threeRowChainJoined() {
        #expect(join("alpha beta gamma\ndelta epsilon zeta\neta") == "alpha beta gamma delta epsilon zeta eta")
    }

    @Test func trailingPaddingIgnored() {
        #expect(join("alpha beta gamma   \ndelta") == "alpha beta gamma delta")
    }

    @Test func longWordEndingInsideMarginKeepsSpace() {
        #expect(join("abcdefghijklmnop\nfoo") == "abcdefghijklmnop foo")
    }

    @Test func wordCutAtFullRowJoinsWithoutSpace() {
        #expect(join("abcdefghijklmnopqrst\nuvw") == "abcdefghijklmnopqrstuvw")
    }

    @Test func wordCutAtPaddedRowJoinsWithoutSpace() {
        #expect(join("abcdefghijklmnopqrs\ntuv") == "abcdefghijklmnopqrstuv")
    }

    @Test func wordCutInsideListItemJoinsWithoutSpace() {
        #expect(join("- abcdefghijklmnopq\n  rst") == "- abcdefghijklmnopqrst")
    }

    @Test func mergedRowUsesLastSegmentEnd() {
        #expect(join("alpha beta gamma delta epsilon zeta e\ntheta") == "alpha beta gamma delta epsilon zeta e theta")
    }

    @Test func mergedRowWithoutSpacesKeepsSpace() {
        #expect(join("abcdefghijklmnopqrstuvwxyzabcdefghijk\ntheta") == "abcdefghijklmnopqrstuvwxyzabcdefghijk theta")
    }

    @Test func partialFirstRowWithLeadingSpacesJoins() {
        #expect(join("  gamma delta\n      eta", start: 4) == "  gamma delta eta")
    }

    @Test func partialFirstRowWithShallowNextIndentKept() {
        let text = "  gamma delta\n  eta"
        #expect(join(text, start: 4) == text)
    }

    @Test func inlineCodeAndIssueRefsAreNotBlocks() {
        #expect(join("alpha beta gamma\n`code` delta") == "alpha beta gamma `code` delta")
        #expect(join("alpha beta gamma\n#12 delta") == "alpha beta gamma #12 delta")
    }

    @Test func fencesAndHeadingsAreBlocks() {
        let fence = "alpha beta gamma\n```swift"
        let heading = "alpha beta gamma\n## Title"
        #expect(join(fence) == fence)
        #expect(join(heading) == heading)
    }
}
