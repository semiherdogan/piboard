import Testing
@testable import PiBoard

struct TerminalTextTrimmerTests {
    @Test func trailingSpacesRemovedPerLine() {
        let result = TerminalTextTrimmer.trim("foo   \nbar\t\t\n")
        #expect(result == "foo\nbar")
    }

    @Test func leadingIndentationKept() {
        let result = TerminalTextTrimmer.trim("  foo\n    bar")
        #expect(result == "  foo\n    bar")
    }

    @Test func leadingAndTrailingBlankLinesDropped() {
        let result = TerminalTextTrimmer.trim("\n\n  \nfoo\nbar\n\n   \n")
        #expect(result == "foo\nbar")
    }

    @Test func interiorBlankLinesPreserved() {
        let result = TerminalTextTrimmer.trim("foo\n\nbar")
        #expect(result == "foo\n\nbar")
    }

    @Test func nilYieldsEmpty() {
        #expect(TerminalTextTrimmer.trim(nil) == "")
    }

    @Test func allBlankYieldsEmpty() {
        #expect(TerminalTextTrimmer.trim("   \n\t\n") == "")
    }

    @Test func nbspAndTabsTrimmed() {
        let result = TerminalTextTrimmer.trim("foo\u{00A0}\t\nbar")
        #expect(result == "foo\nbar")
    }
}
