import Foundation
import Testing
@testable import PiBoard

struct PiSessionReaderTests {
    private static let header = #"{"type":"session","version":3,"id":"11111111-1111-1111-1111-111111111111","timestamp":"2026-10-06T13:02:02.447Z","cwd":"/tmp/project"}"#
    private static let hugeToolOutput = String(repeating: "x", count: 50_000)

    private func userLine(content: String, timestamp: String = "2026-10-06T13:02:03.000Z") -> String {
        #"{"type":"message","timestamp":"\#(timestamp)","message":{"role":"user","content":\#(content)}}"#
    }

    private func assistantLine(
        content: String,
        model: String = "model-a",
        usage: String,
        timestamp: String = "2026-10-06T13:02:04.000Z"
    ) -> String {
        #"{"type":"message","timestamp":"\#(timestamp)","message":{"role":"assistant","content":\#(content),"model":"\#(model)","provider":"p","stopReason":"stop","usage":\#(usage)}}"#
    }

    private func usageJSON(input: Int, output: Int, cacheRead: Int = 0, cacheWrite: Int = 0, total: Int, cost: Double) -> String {
        #"{"input":\#(input),"output":\#(output),"cacheRead":\#(cacheRead),"cacheWrite":\#(cacheWrite),"totalTokens":\#(total),"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":\#(cost)}}"#
    }

    private func summarize(_ lines: [String]) -> SessionSummary {
        PiSessionReader.summarize(Data(lines.joined(separator: "\n").utf8))
    }

    @Test func countsTurnsAndAssistantMessages() {
        let summary = summarize([
            Self.header,
            #"{"type":"session_info","name":"proje"}"#,
            userLine(content: #"[{"type":"text","text":"Do it"}]"#),
            assistantLine(content: #"[{"type":"text","text":"Hello"}]"#, usage: usageJSON(input: 10, output: 5, cacheRead: 100, total: 115, cost: 0.01)),
            #"{"type":"message","timestamp":"2026-10-06T13:02:05.000Z","message":{"role":"toolResult","content":[{"type":"text","text":"\#(Self.hugeToolOutput)"}]}}"#,
            userLine(content: #""Again""#),
            assistantLine(content: #"[{"type":"toolCall","id":"c1","name":"bash","arguments":{}}]"#, usage: usageJSON(input: 0, output: 0, total: 0, cost: 0.02))
        ])

        #expect(summary.turnCount == 2)
        #expect(summary.assistantMessageCount == 2)
        #expect(summary.lastAssistantText == "Hello")
        #expect(summary.name == "proje")
        #expect(summary.usage.input == 10)
        #expect(summary.usage.output == 5)
        #expect(summary.usage.cacheRead == 100)
        #expect(summary.usage.total == 115)
        #expect(abs(summary.usage.cost - 0.03) < 0.000_001)
        #expect(summary.model == "model-a")
    }

    @Test func modelChangeWins() {
        let summary = summarize([
            Self.header,
            assistantLine(content: #"[{"type":"text","text":"Hi"}]"#, model: "model-a", usage: usageJSON(input: 1, output: 1, total: 2, cost: 0)),
            #"{"type":"model_change","timestamp":"2026-10-06T13:02:06.000Z","provider":"p","modelId":"model-b"}"#,
            assistantLine(content: #"[{"type":"text","text":"Again"}]"#, model: "model-a", usage: usageJSON(input: 1, output: 1, total: 2, cost: 0))
        ])

        #expect(summary.model == "model-b")
    }

    @Test func usageEntriesCountTowardTotals() {
        let summary = summarize([
            Self.header,
            #"{"type":"usage","usage":\#(usageJSON(input: 7, output: 3, total: 10, cost: 0.5))}"#,
            #"{"type":"compaction","summary":"s","usage":\#(usageJSON(input: 2, output: 1, total: 3, cost: 0.25))}"#,
            #"{"type":"branch_summary","summary":"s"}"#
        ])

        #expect(summary.usage.input == 9)
        #expect(summary.usage.output == 4)
        #expect(summary.usage.total == 13)
        #expect(abs(summary.usage.cost - 0.75) < 0.000_001)
    }

    @Test func lastActivityIsTheNewestTimestamp() throws {
        let summary = summarize([
            Self.header,
            userLine(content: #""Late""#, timestamp: "2026-10-06T14:00:00.000Z"),
            userLine(content: #""Early""#, timestamp: "2026-10-06T13:00:00.000Z")
        ])

        #expect(summary.lastActivity == ISO8601Format.date(from: "2026-10-06T14:00:00.000Z"))
    }

    @Test func firstLineOfLastMessageSkipsBlankLines() {
        var summary = SessionSummary()
        summary.lastAssistantText = "\n\n  Done.\nmore"

        #expect(summary.firstLineOfLastMessage == "Done.")
    }

    @Test func garbageLinesAreIgnored() {
        let summary = summarize([
            "not json at all \"role\":\"user\"",
            "",
            userLine(content: #""Hello""#)
        ])

        #expect(summary.turnCount == 1)
    }

    @Test func readsAFileFromDisk() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data([Self.header, userLine(content: #""Hello""#)].joined(separator: "\n").utf8).write(to: file)

        let summary = try PiSessionReader.read(file: file)

        #expect(summary.turnCount == 1)
    }
}
