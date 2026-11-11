import Testing
@testable import PiBoard

struct ANSIStripperTests {
    @Test func removesColorSequences() {
        #expect(ANSIStripper.strip("\u{1B}[31mred\u{1B}[0m text") == "red text")
    }

    @Test func removesOSCTerminatedByBellOrStringTerminator() {
        #expect(ANSIStripper.strip("a\u{1B}]8;;https://x.test\u{07}link\u{1B}]8;;\u{07}b") == "alinkb")
        #expect(ANSIStripper.strip("a\u{1B}]0;title\u{1B}\\b") == "ab")
    }

    @Test func leavesPlainTextUntouched() {
        #expect(ANSIStripper.strip("plain [text]") == "plain [text]")
    }
}
