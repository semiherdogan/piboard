import Foundation
import Testing
@testable import PiBoard

struct TerminalProgressScannerTests {
    private let working = Array("\u{1b}]9;4;3\u{07}".utf8)
    private let idle = Array("\u{1b}]9;4;0\u{07}".utf8)

    private func bytes(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    @Test func findsATurnStartingAndEnding() {
        var scanner = TerminalProgressScanner()
        #expect(scanner.scan(working) == [.working])
        #expect(scanner.scan(idle) == [.idle])
    }

    @Test func ignoresOrdinaryOutput() {
        var scanner = TerminalProgressScanner()
        #expect(scanner.scan(bytes("building the project...\n")).isEmpty)
        // Other escape sequences must not be mistaken for progress.
        #expect(scanner.scan(bytes("\u{1b}[2J\u{1b}]0;title\u{07}\u{1b}[31m")).isEmpty)
    }

    @Test func readsSequencesSurroundedByOutput() {
        var scanner = TerminalProgressScanner()
        let chunk = bytes("done\n") + idle + bytes("> ")
        #expect(scanner.scan(chunk) == [.idle])
    }

    // The pty hands over whatever happens to be buffered, so a sequence can arrive in pieces.
    @Test func joinsASequenceSplitAcrossReads() {
        var scanner = TerminalProgressScanner()
        #expect(scanner.scan(Array(working[0..<3])).isEmpty)
        #expect(scanner.scan(Array(working[3...])) == [.working])
    }

    @Test func joinsASequenceSplitIntoSingleBytes() {
        var scanner = TerminalProgressScanner()
        var found: [AgentActivity] = []
        for byte in idle {
            found += scanner.scan([byte])
        }
        #expect(found == [.idle])
    }

    // A sequence that already matched must not match again through the carried-over bytes.
    @Test func doesNotReportTheSameSequenceTwice() {
        var scanner = TerminalProgressScanner()
        #expect(scanner.scan(working) == [.working])
        #expect(scanner.scan(bytes("output")).isEmpty)
        #expect(scanner.scan(bytes("more output")).isEmpty)
    }

    @Test func readsSeveralSequencesInOneChunk() {
        var scanner = TerminalProgressScanner()
        #expect(scanner.scan(working + bytes("x") + idle + working) == [.working, .idle, .working])
    }

    @Test func keepaliveRepeatsAreAllReported() {
        var scanner = TerminalProgressScanner()
        #expect(scanner.scan(working + working) == [.working, .working])
    }
}
