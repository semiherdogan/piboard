import Foundation
import Testing
@testable import PiBoard

struct TerminalTitleScannerTests {
    private func title(_ text: String, command: String = "0", terminator: String = "\u{07}") -> [UInt8] {
        Array("\u{1b}]\(command);\(text)\(terminator)".utf8)
    }

    @Test func workingGlyphIsWorking() {
        var scanner = TerminalTitleScanner()
        #expect(scanner.scan(title("\u{25D0} task")) == [.working])
        #expect(scanner.scan(title("\u{25D1} task")) == [.working])
    }

    @Test func otherSpinnerFramesAreWorking() {
        var scanner = TerminalTitleScanner()
        #expect(scanner.scan(title("\u{25D2} task")) == [.working])
        #expect(scanner.scan(title("\u{25D3} task")) == [.working])
    }

    @Test func idleGlyphIsIdle() {
        var scanner = TerminalTitleScanner()
        #expect(scanner.scan(title("\u{2733} task")) == [.idle])
    }

    @Test func unknownGlyphAndEmptyTitleGiveNothing() {
        var scanner = TerminalTitleScanner()
        #expect(scanner.scan(title("claude")).isEmpty)
        #expect(scanner.scan(title("")).isEmpty)
    }

    @Test func osc2WorksLikeOsc0() {
        var scanner = TerminalTitleScanner()
        #expect(scanner.scan(title("\u{25D0} task", command: "2")) == [.working])
    }

    @Test func titleSplitInsideTheGlyphIsReportedOnce() {
        var scanner = TerminalTitleScanner()
        let bytes = title("\u{25D0} task")
        // ESC ] 0 ; then the first byte of the three-byte glyph.
        let split = 5
        #expect(scanner.scan(bytes[..<split]).isEmpty)
        #expect(scanner.scan(bytes[split...]) == [.working])
    }

    @Test func titleSplitBeforeTheBellIsReportedOnce() {
        var scanner = TerminalTitleScanner()
        let bytes = title("\u{2733} task")
        #expect(scanner.scan(bytes.dropLast()).isEmpty)
        #expect(scanner.scan(bytes.suffix(1)) == [.idle])
    }

    @Test func stringTerminatorEndsTheTitle() {
        var scanner = TerminalTitleScanner()
        #expect(scanner.scan(title("\u{25D0} task", terminator: "\u{1b}\\")) == [.working])
    }

    @Test func overlongTitleIsDroppedAndScannerRecovers() {
        var scanner = TerminalTitleScanner()
        let long = "\u{25D0}" + String(repeating: "a", count: 300)
        #expect(scanner.scan(title(long)).isEmpty)
        #expect(scanner.scan(title("\u{2733} task")) == [.idle])
    }

    @Test func plainTextAndProgressSequencesGiveNothing() {
        var scanner = TerminalTitleScanner()
        #expect(scanner.scan(Array("building...\n".utf8)).isEmpty)
        #expect(scanner.scan(Array("\u{1b}]9;4;3\u{07}".utf8)).isEmpty)
    }

    @Test func twoTitlesInOneChunkAreReportedInOrder() {
        var scanner = TerminalTitleScanner()
        let chunk = title("\u{25D0} task") + title("\u{2733} task")
        #expect(scanner.scan(chunk) == [.working, .idle])
    }
}
