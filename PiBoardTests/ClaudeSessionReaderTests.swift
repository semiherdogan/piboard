import Foundation
import Testing
@testable import PiBoard

struct ClaudeSessionReaderTests {
    private let lines = [
        #"{"type":"custom-title","customTitle":"spike","sessionId":"s"}"#,
        #"{"type":"user","timestamp":"2026-10-29T19:26:50.000Z","message":{"role":"user","content":"Run ls"}}"#,
        #"{"type":"assistant","timestamp":"2026-10-29T19:26:55.473Z","message":{"role":"assistant","model":"claude-opus-5-5","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}],"usage":{"input_tokens":2,"cache_creation_input_tokens":5816,"cache_read_input_tokens":11910,"output_tokens":76}}}"#,
        #"{"type":"user","timestamp":"2026-10-29T19:26:56.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#,
        #"{"type":"assistant","timestamp":"2026-10-29T19:26:57.670Z","message":{"role":"assistant","model":"claude-opus-5-5","content":[{"type":"text","text":"I ran it."}],"usage":{"input_tokens":2,"cache_creation_input_tokens":5019,"cache_read_input_tokens":17726,"output_tokens":147}}}"#,
        #"{"type":"cost-state","totalCostUSD":0.0970832}"#,
        "not json"
    ]

    @Test func summarizesAFixture() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("piboard-claude-\(UUID().uuidString).jsonl")
        try Data(lines.joined(separator: "\n").utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let summary = try ClaudeSessionReader.read(file: file)

        #expect(summary.name == "spike")
        #expect(summary.turnCount == 1)
        #expect(summary.assistantMessageCount == 2)
        #expect(summary.model == "claude-opus-5-5")
        #expect(summary.usage.input == 4)
        #expect(summary.usage.output == 223)
        #expect(summary.usage.cacheRead == 29636)
        #expect(summary.usage.cacheWrite == 10835)
        #expect(summary.usage.total == 4 + 223 + 29636 + 10835)
        #expect(summary.usage.cost == 0.0970832)
        #expect(summary.lastAssistantText == "I ran it.")
        #expect(summary.lastActivity == ISO8601Format.date(from: "2026-10-29T19:26:57.670Z"))
    }

    @Test func entriesSharingAMessageIDCountOnce() throws {
        let usage = #""usage":{"input_tokens":3,"cache_creation_input_tokens":10,"cache_read_input_tokens":20,"output_tokens":7}"#
        let entries = [
            #"{"type":"assistant","timestamp":"2026-10-29T19:26:55.000Z","message":{"id":"msg_1","role":"assistant","model":"claude-opus-5-5","content":[{"type":"thinking","thinking":"hm"}],"#
                + usage + "}}",
            #"{"type":"assistant","timestamp":"2026-10-29T19:26:56.000Z","message":{"id":"msg_1","role":"assistant","model":"claude-opus-5-5","content":[{"type":"text","text":"Done."}],"#
                + usage + "}}",
        ]
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("piboard-claude-\(UUID().uuidString).jsonl")
        try Data(entries.joined(separator: "\n").utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let summary = try ClaudeSessionReader.read(file: file)

        #expect(summary.assistantMessageCount == 1)
        #expect(summary.usage.input == 3)
        #expect(summary.usage.output == 7)
        #expect(summary.usage.cacheRead == 20)
        #expect(summary.usage.cacheWrite == 10)
        #expect(summary.lastAssistantText == "Done.")
    }

    @Test func acceptsTimestampsWithoutFractionalSeconds() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("piboard-claude-\(UUID().uuidString).jsonl")
        try Data(#"{"type":"user","timestamp":"2026-10-29T19:26:50Z","message":{"content":"hi"}}"#.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let summary = try ClaudeSessionReader.read(file: file)

        #expect(summary.lastActivity == Date(timeIntervalSince1970: 1_793_302_010))
    }
}
