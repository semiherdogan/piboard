import Foundation
import Testing
@testable import PiBoard

struct PiRPCCodecTests {
    // MARK: Helpers

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func events(_ json: String) -> [ConversationEvent] {
        if case .events(let events) = PiRPCCodec.decode(Data(json.utf8)) { return events }
        return []
    }

    private func response(_ json: String) -> PiRPCResponse? {
        if case .response(let response) = PiRPCCodec.decode(Data(json.utf8)) { return response }
        return nil
    }

    private func json(_ text: String) -> JSONValue? {
        JSONValue(data: Data(text.utf8))
    }

    // MARK: Encoding

    @Test func encodesAPlainPromptWithoutStreamingBehavior() throws {
        let data = PiRPCCodec.encode(.prompt(message: "hi", images: [], streaming: nil), id: "r1")
        #expect(data.last == UInt8(ascii: "\n"))
        #expect(data.filter { $0 == UInt8(ascii: "\n") }.count == 1)
        let encoded = try object(data)
        #expect(encoded["type"] as? String == "prompt")
        #expect(encoded["id"] as? String == "r1")
        #expect(encoded["message"] as? String == "hi")
        #expect(encoded["streamingBehavior"] == nil)
        #expect(encoded["images"] == nil)
    }

    @Test func encodesImagesAsBase64AndStreamingBehavior() throws {
        let image = PromptImage(data: Data([0xFF, 0xEE, 0xDD]), mimeType: "image/png")
        let steer = try object(PiRPCCodec.encode(.prompt(message: "m", images: [image], streaming: .steer), id: "r"))
        #expect(steer["streamingBehavior"] as? String == "steer")
        let images = try #require(steer["images"] as? [[String: String]])
        #expect(images == [["type": "image", "data": image.data.base64EncodedString(), "mimeType": "image/png"]])

        let followUp = try object(PiRPCCodec.encode(.prompt(message: "m", images: [], streaming: .followUp), id: "r"))
        #expect(followUp["streamingBehavior"] as? String == "followUp")
    }

    @Test func encodesCommandsWithTheirWireTypeAndId() throws {
        let cases: [(PiRPCCommand, String)] = [
            (.abort, "abort"),
            (.clearQueue, "clear_queue"),
            (.getState, "get_state"),
            (.getMessages, "get_messages"),
            (.getSessionStats, "get_session_stats"),
            (.getAvailableModels, "get_available_models"),
            (.getAvailableThinkingLevels, "get_available_thinking_levels"),
            (.getCommands, "get_commands"),
        ]
        for (command, type) in cases {
            let encoded = try object(PiRPCCodec.encode(command, id: "id-1"))
            #expect(encoded["type"] as? String == type)
            #expect(encoded["id"] as? String == "id-1")
        }
    }

    @Test func encodesThinkingLevelAndModel() throws {
        let level = try object(PiRPCCodec.encode(.setThinkingLevel("high"), id: "i"))
        #expect(level["type"] as? String == "set_thinking_level")
        #expect(level["level"] as? String == "high")

        let model = try object(PiRPCCodec.encode(.setModel(provider: "anthropic", modelID: "sonnet"), id: "i"))
        #expect(model["type"] as? String == "set_model")
        #expect(model["provider"] as? String == "anthropic")
        #expect(model["modelId"] as? String == "sonnet")
    }

    @Test func encodesExtensionUIResponsesWithTheDialogId() throws {
        let value = try object(PiRPCCodec.encode(.extensionUIResponse(id: "d1", answer: .value("Allow")), id: "ignored"))
        #expect(value["type"] as? String == "extension_ui_response")
        #expect(value["id"] as? String == "d1")
        #expect(value["value"] as? String == "Allow")

        let confirmed = try object(PiRPCCodec.encode(.extensionUIResponse(id: "d2", answer: .confirmed(true)), id: "ignored"))
        #expect(confirmed["confirmed"] as? Bool == true)
        #expect(confirmed["id"] as? String == "d2")

        let cancelled = try object(PiRPCCodec.encode(.extensionUIResponse(id: "d3", answer: .cancelled), id: "ignored"))
        #expect(cancelled["cancelled"] as? Bool == true)
        #expect(cancelled["value"] == nil)
    }

    // MARK: Responses

    @Test func decodesAResponseWithAndWithoutAnId() throws {
        let withID = try #require(response(#"{"id":"r1","type":"response","command":"prompt","success":true,"data":{"disposition":"started"}}"#))
        #expect(withID.id == "r1")
        #expect(withID.command == "prompt")
        #expect(withID.success)
        #expect(PiRPCCodec.disposition(from: withID.data) == .started)

        let failed = try #require(response(#"{"type":"response","command":"steer","success":false,"error":"nope"}"#))
        #expect(failed.id == nil)
        #expect(!failed.success)
        #expect(failed.error == "nope")
    }

    // MARK: Run and turn events

    @Test func decodesRunAndTurnLifecycle() {
        #expect(events(#"{"type":"agent_start"}"#) == [.runStarted])
        #expect(events(#"{"type":"agent_settled","aborted":false}"#) == [.runSettled(aborted: false)])
        #expect(events(#"{"type":"agent_settled","aborted":true}"#) == [.runSettled(aborted: true)])
        #expect(events(#"{"type":"turn_start"}"#) == [.turnStarted])
        #expect(events(#"{"type":"turn_end","message":{"role":"assistant"},"toolResults":[]}"#) == [.turnEnded])
        #expect(PiRPCCodec.decode(Data(#"{"type":"agent_end","messages":[],"willRetry":false}"#.utf8)) == nil)
    }

    // MARK: Streaming updates

    @Test func decodesTextAndThinkingUpdates() {
        let delta = #"{"type":"message_update","usage":{"input":0,"output":0,"totalTokens":0},"assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hello"}}"#
        #expect(events(delta) == [.textDelta(index: 0, delta: "Hello")])
        let end = #"{"type":"message_update","assistantMessageEvent":{"type":"text_end","contentIndex":2,"content":"Hello world"}}"#
        #expect(events(end) == [.textEnded(index: 2, content: "Hello world")])
        let think = #"{"type":"message_update","assistantMessageEvent":{"type":"thinking_delta","contentIndex":0,"delta":"hm"}}"#
        #expect(events(think) == [.thinkingDelta(index: 0, delta: "hm")])
        let thinkEnd = #"{"type":"message_update","assistantMessageEvent":{"type":"thinking_end","contentIndex":0,"content":"hmm"}}"#
        #expect(events(thinkEnd) == [.thinkingEnded(index: 0, content: "hmm")])
    }

    @Test func addsAUsageEventWhenTheUpdateReportsTokens() {
        let line = #"{"type":"message_update","usage":{"input":100,"output":1,"cacheRead":0,"cacheWrite":0,"totalTokens":101,"cost":{"total":0.25}},"assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hello "}}"#
        #expect(events(line) == [
            .textDelta(index: 0, delta: "Hello "),
            .usageUpdated(ConversationUsage(input: 100, output: 1, total: 101, cost: 0.25)),
        ])
    }

    @Test func ignoresBlockStartsAndToolCallDeltas() {
        #expect(PiRPCCodec.decode(Data(#"{"type":"message_update","assistantMessageEvent":{"type":"text_start","contentIndex":0}}"#.utf8)) == nil)
        #expect(PiRPCCodec.decode(Data(#"{"type":"message_update","assistantMessageEvent":{"type":"toolcall_delta","contentIndex":1,"delta":"{\"co"}}"#.utf8)) == nil)
    }

    @Test func decodesToolCallStartAndEndWithReserialisedArguments() {
        let start = #"{"type":"message_update","assistantMessageEvent":{"type":"toolcall_start","contentIndex":1,"id":"call_1","toolName":"bash"}}"#
        #expect(events(start) == [.toolCallStarted(index: 1, id: "call_1", name: "bash")])
        let end = #"{"type":"message_update","assistantMessageEvent":{"type":"toolcall_end","contentIndex":1,"toolCall":{"type":"toolCall","id":"call_1","name":"bash","arguments":{"timeout":5,"command":"ls -la /tmp"}}}}"#
        #expect(events(end) == [.toolCallEnded(index: 1, id: "call_1", name: "bash", argumentsJSON: #"{"command":"ls -la /tmp","timeout":5}"#)])
    }

    // MARK: Messages

    @Test func decodesAnAssistantMessageWithThinkingAndText() {
        let line = #"{"type":"message_end","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hm"},{"type":"text","text":"hi"}],"model":"m1","stopReason":"stop","timestamp":1733234401000,"usage":{"input":1,"output":2,"cacheRead":3,"cacheWrite":4,"reasoning":1,"totalTokens":10,"cost":{"input":0,"total":0.5}}}}"#
        let expected = ConversationMessage(
            role: .assistant,
            blocks: [.thinking("hm"), .text("hi")],
            timestamp: Date(timeIntervalSince1970: 1_733_234_401),
            stopReason: "stop",
            usage: ConversationUsage(input: 1, output: 2, cacheRead: 3, cacheWrite: 4, reasoning: 1, total: 10, cost: 0.5),
            model: "m1"
        )
        #expect(events(line) == [.messageEnded(expected)])
    }

    @Test func decodesAnAbortedAssistantMessage() {
        let line = #"{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"1"}],"stopReason":"aborted","errorMessage":"stream ended","usage":{"input":0,"output":0,"totalTokens":0,"cost":{"total":0}}}}"#
        guard case .messageEnded(let message)? = events(line).first else {
            Issue.record("expected messageEnded")
            return
        }
        #expect(message.stopReason == "aborted")
        #expect(message.errorMessage == "stream ended")
        #expect(message.blocks == [.text("1")])
        #expect(message.usage == .zero)
    }

    @Test func decodesAUserMessageWithAnImageBlock() {
        let line = #"{"type":"message_end","message":{"role":"user","content":[{"type":"text","text":"look"},{"type":"image","data":"AAAA","mimeType":"image/png"}],"timestamp":1}}"#
        guard case .messageEnded(let message)? = events(line).first else {
            Issue.record("expected messageEnded")
            return
        }
        #expect(message.role == .user)
        #expect(message.blocks == [.text("look"), .image(mimeType: "image/png")])
    }

    @Test func decodesAUserMessageWithPlainStringContent() {
        let line = #"{"type":"message_start","message":{"role":"user","content":"Review this","timestamp":1733234401000}}"#
        #expect(events(line) == [.messageStarted(role: .user)])
        let end = #"{"type":"message_end","message":{"role":"user","content":"Review this","timestamp":1733234401000}}"#
        guard case .messageEnded(let message)? = events(end).first else {
            Issue.record("expected messageEnded")
            return
        }
        #expect(message.blocks == [.text("Review this")])
    }

    @Test func decodesAToolResultMessage() {
        let line = #"{"type":"message_end","message":{"role":"toolResult","toolCallId":"c1","toolName":"read","content":[{"type":"text","text":"a"},{"type":"text","text":"b"}],"isError":true,"timestamp":1}}"#
        guard case .messageEnded(let message)? = events(line).first else {
            Issue.record("expected messageEnded")
            return
        }
        #expect(message.role == .toolResult)
        #expect(message.blocks == [.toolResult(toolCallID: "c1", text: "a\nb", isError: true)])
    }

    @Test func decodesAnAssistantToolCallBlock() {
        let line = #"{"type":"message_end","message":{"role":"assistant","content":[{"type":"toolCall","id":"c1","name":"bash","arguments":{"command":"ls"}}]}}"#
        guard case .messageEnded(let message)? = events(line).first else {
            Issue.record("expected messageEnded")
            return
        }
        #expect(message.blocks == [.toolCall(id: "c1", name: "bash", argumentsJSON: #"{"command":"ls"}"#)])
    }

    // MARK: Tools, queue, compaction, retry

    @Test func decodesToolExecution() {
        let start = #"{"type":"tool_execution_start","toolCallId":"call_abc123","toolName":"bash","args":{"command":"ls -la"}}"#
        #expect(events(start) == [.toolExecutionStarted(id: "call_abc123", name: "bash", argumentsJSON: #"{"command":"ls -la"}"#)])
        let end = #"{"type":"tool_execution_end","toolCallId":"call_abc123","toolName":"bash","result":{"content":[{"type":"text","text":"complete output"}],"details":{}},"isError":false,"durationMs":12}"#
        #expect(events(end) == [.toolExecutionEnded(id: "call_abc123", name: "bash", resultText: "complete output", isError: false, durationMs: 12)])
    }

    @Test func decodesQueueUpdates() {
        #expect(events(#"{"type":"queue_update","steering":["Stop"],"followUp":[]}"#) == [.queueChanged(steering: ["Stop"], followUp: [])])
    }

    @Test func decodesCompaction() {
        #expect(events(#"{"type":"compaction_start","reason":"threshold"}"#) == [.compactionStarted(reason: "threshold")])
        #expect(events(#"{"type":"compaction_end","reason":"threshold","result":{"summary":"S"},"aborted":false,"willRetry":false}"#)
            == [.compactionEnded(summary: "S", aborted: false, errorMessage: nil)])
        #expect(events(#"{"type":"compaction_end","aborted":true}"#) == [.compactionEnded(summary: nil, aborted: true, errorMessage: nil)])
        #expect(events(#"{"type":"compaction_end","aborted":false,"errorMessage":"boom"}"#)
            == [.compactionEnded(summary: nil, aborted: false, errorMessage: "boom")])
    }

    @Test func decodesRetries() {
        #expect(events(#"{"type":"auto_retry_start","attempt":1,"maxAttempts":3,"delayMs":2000,"errorMessage":"529 overloaded"}"#)
            == [.retryScheduled(attempt: 1, maxAttempts: 3, errorMessage: "529 overloaded")])
        #expect(events(#"{"type":"auto_retry_end","success":true,"attempt":2}"#) == [.retryFinished(success: true, finalError: nil)])
        #expect(events(#"{"type":"auto_retry_end","success":false,"finalError":"gave up"}"#) == [.retryFinished(success: false, finalError: "gave up")])
        #expect(events(#"{"type":"summarization_retry_scheduled","attempt":1,"maxAttempts":3,"delayMs":2000,"errorMessage":"terminated"}"#)
            == [.retryScheduled(attempt: 1, maxAttempts: 3, errorMessage: "terminated")])
    }

    @Test func decodesSessionAndExtensionEvents() {
        #expect(events(#"{"type":"session_info_changed","name":"My work"}"#) == [.sessionNameChanged("My work")])
        #expect(events(#"{"type":"session_info_changed"}"#) == [.sessionNameChanged(nil)])
        #expect(events(#"{"type":"thinking_level_changed","level":"low"}"#) == [.thinkingLevelChanged("low")])
        #expect(events(#"{"type":"extension_error","extensionPath":"/x.ts","event":"tool_call","error":"Error message"}"#) == [.extensionError("Error message")])
    }

    // MARK: Extension UI

    @Test func decodesDialogRequests() {
        #expect(events(#"{"type":"extension_ui_request","id":"u1","method":"select","title":"Allow?","options":["Allow","Block"],"timeout":10000}"#)
            == [.dialogRequested(ConversationDialog(id: "u1", method: .select, title: "Allow?", options: ["Allow", "Block"], timeoutMs: 10000))])
        #expect(events(#"{"type":"extension_ui_request","id":"u2","method":"confirm","title":"Clear?","message":"All gone."}"#)
            == [.dialogRequested(ConversationDialog(id: "u2", method: .confirm, title: "Clear?", message: "All gone."))])
        #expect(events(#"{"type":"extension_ui_request","id":"u3","method":"input","title":"Value","placeholder":"type"}"#)
            == [.dialogRequested(ConversationDialog(id: "u3", method: .input, title: "Value", placeholder: "type"))])
        #expect(events(#"{"type":"extension_ui_request","id":"u4","method":"editor","title":"Edit","prefill":"L1\nL2"}"#)
            == [.dialogRequested(ConversationDialog(id: "u4", method: .editor, title: "Edit", prefill: "L1\nL2"))])
    }

    @Test func decodesNotifyAndStatus() {
        #expect(events(#"{"type":"extension_ui_request","id":"u5","method":"notify","message":"Blocked","notifyType":"warning"}"#) == [.notified(message: "Blocked")])
        #expect(events(#"{"type":"extension_ui_request","id":"u6","method":"setStatus","statusKey":"usage","statusText":"\u001b[31m42%\u001b[0m"}"#)
            == [.statusChanged(key: "usage", text: "42%")])
        #expect(events(#"{"type":"extension_ui_request","id":"u7","method":"setStatus","statusKey":"usage"}"#) == [.statusChanged(key: "usage", text: nil)])
        #expect(events(#"{"type":"extension_ui_request","id":"u8","method":"setStatus","statusKey":"usage","statusText":""}"#) == [.statusChanged(key: "usage", text: nil)])
    }

    @Test func ignoresUnsupportedRecords() {
        let ignored = [
            #"{"type":"extension_ui_request","id":"w","method":"setWidget","widgetKey":"k","widgetLines":["a"]}"#,
            #"{"type":"extension_ui_request","id":"t","method":"setTitle","title":"pi"}"#,
            #"{"type":"extension_ui_request","id":"e","method":"set_editor_text","text":"x"}"#,
            #"{"type":"bash_execution_update","id":"req-1","delta":"out"}"#,
            #"{"type":"entry_appended","entry":{}}"#,
            #"{"type":"something_new","x":1}"#,
            #"not json"#,
            #"[1,2]"#,
        ]
        for line in ignored {
            #expect(PiRPCCodec.decode(Data(line.utf8)) == nil, "\(line)")
        }
    }

    // MARK: Payloads

    @Test func decodesSessionState() throws {
        let data = json(#"{"model":{"id":"gpt","provider":"openai","reasoning":true,"input":["text","image"],"contextWindow":272000},"thinkingLevel":"medium","isStreaming":true,"sessionFile":"/s/a.jsonl","sessionId":"abc","sessionName":"work","messageCount":5}"#)
        let info = try #require(PiRPCCodec.sessionInfo(from: data))
        #expect(info == ConversationSessionInfo(
            sessionID: "abc",
            sessionFile: "/s/a.jsonl",
            sessionName: "work",
            modelID: "gpt",
            provider: "openai",
            thinkingLevel: "medium",
            isStreaming: true,
            messageCount: 5
        ))
        #expect(PiRPCCodec.sessionInfo(from: json(#"{"thinkingLevel":"low"}"#)) == nil)
    }

    @Test func decodesSessionStats() throws {
        let data = json(#"{"userMessages":5,"assistantMessages":4,"toolCalls":12,"tokens":{"input":50000,"output":10000,"cacheRead":40000,"cacheWrite":5000,"total":105000},"cost":0.45,"contextUsage":{"tokens":60000,"contextWindow":200000,"percent":30}}"#)
        let stats = try #require(PiRPCCodec.stats(from: data))
        #expect(stats.usage == ConversationUsage(input: 50000, output: 10000, cacheRead: 40000, cacheWrite: 5000, total: 105000, cost: 0.45))
        #expect(stats.userMessages == 5)
        #expect(stats.assistantMessages == 4)
        #expect(stats.toolCalls == 12)
        #expect(stats.contextTokens == 60000)
        #expect(stats.contextWindow == 200000)
        #expect(stats.contextPercent == 30)
    }

    @Test func decodesStatsWithoutContextUsage() throws {
        let stats = try #require(PiRPCCodec.stats(from: json(#"{"userMessages":1,"contextUsage":{"tokens":null,"contextWindow":1000,"percent":null}}"#)))
        #expect(stats.contextTokens == nil)
        #expect(stats.contextWindow == 1000)
        #expect(stats.contextPercent == nil)
    }

    @Test func decodesAvailableModels() {
        let data = json(#"{"models":[{"id":"a","name":"Model A","provider":"p","reasoning":true,"input":["text","image"],"contextWindow":1000},{"id":"b","provider":"q","input":["text"]}]}"#)
        #expect(PiRPCCodec.models(from: data) == [
            ConversationModel(id: "a", provider: "p", name: "Model A", reasoning: true, acceptsImages: true, contextWindow: 1000),
            ConversationModel(id: "b", provider: "q", name: "b", reasoning: false, acceptsImages: false, contextWindow: nil),
        ])
    }

    @Test func decodesCommandsAndThinkingLevels() {
        let commands = json(#"{"commands":[{"name":"fix-tests","description":"Fix failing tests","source":"prompt"},{"name":"ext","source":"extension"}]}"#)
        #expect(PiRPCCodec.commands(from: commands) == [
            ConversationCommand(name: "fix-tests", description: "Fix failing tests", source: "prompt"),
            ConversationCommand(name: "ext", description: nil, source: "extension"),
        ])
        #expect(PiRPCCodec.thinkingLevels(from: json(#"{"levels":["off","low"]}"#)) == ["off", "low"])
    }

    @Test func decodesMessagesAndQueue() {
        let data = json(#"{"messages":[{"role":"user","content":"hi","timestamp":1},{"role":"custom","customType":"x","content":"c","display":true}]}"#)
        let messages = PiRPCCodec.messages(from: data)
        #expect(messages.map(\.role) == [.user, .custom])
        let queue = PiRPCCodec.queue(from: json(#"{"steering":["a"],"followUp":["b","c"]}"#))
        #expect(queue.steering == ["a"])
        #expect(queue.followUp == ["b", "c"])
    }

    @Test func decodesCompactionAndBranchSummariesAsTextBlocks() {
        let data = json(#"{"messages":[{"role":"compactionSummary","summary":"folded","tokensBefore":9,"timestamp":1},{"role":"branchSummary","summary":"forked","fromId":"x","timestamp":2}]}"#)
        let messages = PiRPCCodec.messages(from: data)
        #expect(messages.map(\.role) == [.compactionSummary, .compactionSummary])
        #expect(messages.map(\.blocks) == [[.text("folded")], [.text("forked")]])
    }

    @Test func dispositionDefaultsToStarted() {
        #expect(PiRPCCodec.disposition(from: nil) == .started)
        #expect(PiRPCCodec.disposition(from: json(#"{"disposition":"queued"}"#)) == .queued)
        #expect(PiRPCCodec.disposition(from: json(#"{"disposition":"handled"}"#)) == .handled)
    }
}
