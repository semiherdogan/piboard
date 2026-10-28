import Foundation
import Testing
@testable import PiBoard

struct SSEParserTests {
    private func feed(_ parser: inout SSEParser, _ text: String) -> [SSEEvent] {
        parser.feed(Array(text.utf8))
    }

    @Test func parsesASingleEvent() {
        var parser = SSEParser()
        #expect(feed(&parser, "data: hello\n\n") == [SSEEvent(event: nil, data: "hello", id: nil)])
    }

    @Test func joinsMultiLineDataWithNewlines() {
        var parser = SSEParser()
        #expect(feed(&parser, "data: one\ndata: two\n\n").map(\.data) == ["one\ntwo"])
    }

    @Test func ignoresCommentLines() {
        var parser = SSEParser()
        #expect(feed(&parser, ": heartbeat\n\n").isEmpty)
        #expect(feed(&parser, ": heartbeat\ndata: x\n\n").map(\.data) == ["x"])
    }

    @Test func handlesCRLFLineEndings() {
        var parser = SSEParser()
        #expect(feed(&parser, "event: a\r\ndata: b\r\n\r\n") == [SSEEvent(event: "a", data: "b", id: nil)])
    }

    @Test func keepsAnIncompleteEventAcrossFeeds() {
        var parser = SSEParser()
        #expect(feed(&parser, "data: par").isEmpty)
        #expect(feed(&parser, "tial\n").isEmpty)
        #expect(feed(&parser, "\n").map(\.data) == ["partial"])
    }

    @Test func readsEventAndIDFields() {
        var parser = SSEParser()
        let events = feed(&parser, "id: 7\nevent: session.execution.started\ndata: {}\n\n")
        #expect(events == [SSEEvent(event: "session.execution.started", data: "{}", id: "7")])
    }

    @Test func returnsEveryEventCompletedByOneChunk() {
        var parser = SSEParser()
        #expect(feed(&parser, "data: a\n\ndata: b\n\ndata: c").map(\.data) == ["a", "b"])
        #expect(feed(&parser, "\n\n").map(\.data) == ["c"])
    }

    @Test func doesNotLeakFieldsIntoTheNextEvent() {
        var parser = SSEParser()
        _ = feed(&parser, "event: a\nid: 1\ndata: x\n\n")
        #expect(feed(&parser, "data: y\n\n") == [SSEEvent(event: nil, data: "y", id: nil)])
    }
}
