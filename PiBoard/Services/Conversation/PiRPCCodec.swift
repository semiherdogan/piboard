import Foundation

/// Wire field names from Pi's `rpc-commands.md`, `json.md` and `rpc-extension-ui.md`.
private enum Field {
    static let type = "type"
    static let id = "id"
    static let command = "command"
    static let success = "success"
    static let data = "data"
    static let error = "error"
    static let message = "message"
    static let messages = "messages"
    static let images = "images"
    static let streamingBehavior = "streamingBehavior"
    static let level = "level"
    static let levels = "levels"
    static let provider = "provider"
    static let modelID = "modelId"
    static let value = "value"
    static let confirmed = "confirmed"
    static let cancelled = "cancelled"
    static let mimeType = "mimeType"
    static let assistantMessageEvent = "assistantMessageEvent"
    static let usage = "usage"
    static let contentIndex = "contentIndex"
    static let delta = "delta"
    static let content = "content"
    static let toolCall = "toolCall"
    static let toolName = "toolName"
    static let toolCallID = "toolCallId"
    static let name = "name"
    static let arguments = "arguments"
    static let args = "args"
    static let result = "result"
    static let isError = "isError"
    static let durationMs = "durationMs"
    static let steering = "steering"
    static let followUp = "followUp"
    static let reason = "reason"
    static let summary = "summary"
    static let aborted = "aborted"
    static let errorMessage = "errorMessage"
    static let attempt = "attempt"
    static let maxAttempts = "maxAttempts"
    static let finalError = "finalError"
    static let method = "method"
    static let title = "title"
    static let options = "options"
    static let placeholder = "placeholder"
    static let prefill = "prefill"
    static let timeout = "timeout"
    static let statusKey = "statusKey"
    static let statusText = "statusText"
    static let role = "role"
    static let text = "text"
    static let thinking = "thinking"
    static let timestamp = "timestamp"
    static let stopReason = "stopReason"
    static let model = "model"
    static let input = "input"
    static let output = "output"
    static let cacheRead = "cacheRead"
    static let cacheWrite = "cacheWrite"
    static let reasoning = "reasoning"
    static let totalTokens = "totalTokens"
    static let cost = "cost"
    static let total = "total"
    static let sessionID = "sessionId"
    static let sessionFile = "sessionFile"
    static let sessionName = "sessionName"
    static let thinkingLevel = "thinkingLevel"
    static let isStreaming = "isStreaming"
    static let messageCount = "messageCount"
    static let userMessages = "userMessages"
    static let assistantMessages = "assistantMessages"
    static let toolCalls = "toolCalls"
    static let tokens = "tokens"
    static let contextUsage = "contextUsage"
    static let contextWindow = "contextWindow"
    static let percent = "percent"
    static let models = "models"
    static let commands = "commands"
    static let description = "description"
    static let source = "source"
    static let disposition = "disposition"
}

private enum RecordType: String {
    case response
    case agentStart = "agent_start"
    case agentSettled = "agent_settled"
    case turnStart = "turn_start"
    case turnEnd = "turn_end"
    case messageStart = "message_start"
    case messageUpdate = "message_update"
    case messageEnd = "message_end"
    case toolExecutionStart = "tool_execution_start"
    case toolExecutionEnd = "tool_execution_end"
    case queueUpdate = "queue_update"
    case compactionStart = "compaction_start"
    case compactionEnd = "compaction_end"
    case autoRetryStart = "auto_retry_start"
    case autoRetryEnd = "auto_retry_end"
    case summarizationRetryScheduled = "summarization_retry_scheduled"
    case sessionInfoChanged = "session_info_changed"
    case thinkingLevelChanged = "thinking_level_changed"
    case extensionError = "extension_error"
    case extensionUIRequest = "extension_ui_request"
}

private enum AssistantEventType: String {
    case textDelta = "text_delta"
    case textEnd = "text_end"
    case thinkingDelta = "thinking_delta"
    case thinkingEnd = "thinking_end"
    case toolCallStart = "toolcall_start"
    case toolCallEnd = "toolcall_end"
}

private enum UIMethod: String {
    case select
    case confirm
    case input
    case editor
    case notify
    case setStatus
}

private enum BlockType: String {
    case text
    case thinking
    case toolCall
    case image
}

private enum RoleName: String {
    case user
    case assistant
    case system
    case toolResult
    case custom
    case compactionSummary
    case branchSummary
}

private enum StreamingBehaviorName {
    static let steer = "steer"
    static let followUp = "followUp"
}

private enum ImageBlock {
    static let type = "image"
}

private let emptyArgumentsJSON = "{}"
private let textBlockSeparator = "\n"
private let millisecondsPerSecond = 1000.0
private let imageModality = "image"

enum PiRPCCodec {
    // MARK: Encoding

    /// One JSON object terminated by LF. `id` correlates the response; it is ignored for UI responses.
    static func encode(_ command: PiRPCCommand, id: String) -> Data {
        var object: [String: Any] = [Field.type: command.wireName]
        switch command {
        case .extensionUIResponse(let dialogID, let answer):
            object[Field.id] = dialogID
            switch answer {
            case .value(let value): object[Field.value] = value
            case .confirmed(let confirmed): object[Field.confirmed] = confirmed
            case .cancelled: object[Field.cancelled] = true
            }
        case .prompt(let message, let images, let streaming):
            object[Field.id] = id
            object[Field.message] = message
            if !images.isEmpty { object[Field.images] = images.map(encodeImage) }
            switch streaming {
            case .steer: object[Field.streamingBehavior] = StreamingBehaviorName.steer
            case .followUp: object[Field.streamingBehavior] = StreamingBehaviorName.followUp
            case nil: break
            }
        case .setThinkingLevel(let level):
            object[Field.id] = id
            object[Field.level] = level
        case .setModel(let provider, let modelID):
            object[Field.id] = id
            object[Field.provider] = provider
            object[Field.modelID] = modelID
        case .abort, .clearQueue, .getState, .getMessages, .getSessionStats,
             .getAvailableModels, .getAvailableThinkingLevels, .getCommands:
            object[Field.id] = id
        }
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        data.append(UInt8(ascii: "\n"))
        return data
    }

    private static func encodeImage(_ image: PromptImage) -> [String: Any] {
        [
            Field.type: ImageBlock.type,
            Field.data: image.data.base64EncodedString(),
            Field.mimeType: image.mimeType,
        ]
    }

    // MARK: Decoding

    /// Nil for anything the chat has no use for: unknown types, widgets, titles, `agent_end`.
    static func decode(_ line: Data) -> PiRPCRecord? {
        guard let root = JSONValue(data: line),
              let typeName = root[Field.type]?.string,
              let type = RecordType(rawValue: typeName)
        else { return nil }

        switch type {
        case .response:
            return decodeResponse(root).map(PiRPCRecord.response)
        case .agentStart:
            return single(.runStarted)
        case .agentSettled:
            return single(.runSettled(aborted: root[Field.aborted]?.bool ?? false))
        case .turnStart:
            return single(.turnStarted)
        case .turnEnd:
            return single(.turnEnded)
        case .messageStart:
            guard let message = root[Field.message].flatMap(decodeMessage) else { return nil }
            return single(.messageStarted(role: message.role))
        case .messageUpdate:
            return decodeMessageUpdate(root)
        case .messageEnd:
            guard let message = root[Field.message].flatMap(decodeMessage) else { return nil }
            return single(.messageEnded(message))
        case .toolExecutionStart:
            guard let id = root[Field.toolCallID]?.string else { return nil }
            return single(.toolExecutionStarted(
                id: id,
                name: root[Field.toolName]?.string ?? "",
                argumentsJSON: root[Field.args]?.serialized ?? emptyArgumentsJSON
            ))
        case .toolExecutionEnd:
            guard let id = root[Field.toolCallID]?.string else { return nil }
            return single(.toolExecutionEnded(
                id: id,
                name: root[Field.toolName]?.string ?? "",
                resultText: joinedText(root[Field.result]?[Field.content]),
                isError: root[Field.isError]?.bool ?? false,
                durationMs: root[Field.durationMs]?.int
            ))
        case .queueUpdate:
            return single(.queueChanged(
                steering: strings(root[Field.steering]),
                followUp: strings(root[Field.followUp])
            ))
        case .compactionStart:
            return single(.compactionStarted(reason: root[Field.reason]?.string ?? ""))
        case .compactionEnd:
            return single(.compactionEnded(
                summary: root[Field.result]?[Field.summary]?.string,
                aborted: root[Field.aborted]?.bool ?? false,
                errorMessage: root[Field.errorMessage]?.string
            ))
        case .autoRetryStart, .summarizationRetryScheduled:
            return single(.retryScheduled(
                attempt: root[Field.attempt]?.int ?? 0,
                maxAttempts: root[Field.maxAttempts]?.int ?? 0,
                errorMessage: root[Field.errorMessage]?.string ?? ""
            ))
        case .autoRetryEnd:
            return single(.retryFinished(
                success: root[Field.success]?.bool ?? false,
                finalError: root[Field.finalError]?.string
            ))
        case .sessionInfoChanged:
            return single(.sessionNameChanged(root[Field.name]?.string))
        case .thinkingLevelChanged:
            guard let level = root[Field.level]?.string else { return nil }
            return single(.thinkingLevelChanged(level))
        case .extensionError:
            return single(.extensionError(root[Field.error]?.string ?? ""))
        case .extensionUIRequest:
            return decodeUIRequest(root)
        }
    }

    private static func single(_ event: ConversationEvent) -> PiRPCRecord {
        .events([event])
    }

    private static func decodeResponse(_ root: JSONValue) -> PiRPCResponse? {
        guard let command = root[Field.command]?.string, let success = root[Field.success]?.bool else { return nil }
        return PiRPCResponse(
            id: root[Field.id]?.string,
            command: command,
            success: success,
            data: root[Field.data],
            error: root[Field.error]?.string
        )
    }

    private static func decodeMessageUpdate(_ root: JSONValue) -> PiRPCRecord? {
        var events: [ConversationEvent] = []
        if let inner = root[Field.assistantMessageEvent], let event = decodeAssistantEvent(inner) {
            events.append(event)
        }
        // Providers that do not report usage while streaming leave it at zero until the message ends.
        if let usage = root[Field.usage].map(decodeUsage), usage.total > 0 {
            events.append(.usageUpdated(usage))
        }
        return events.isEmpty ? nil : .events(events)
    }

    private static func decodeAssistantEvent(_ inner: JSONValue) -> ConversationEvent? {
        guard let typeName = inner[Field.type]?.string, let type = AssistantEventType(rawValue: typeName) else { return nil }
        let index = inner[Field.contentIndex]?.int ?? 0
        switch type {
        case .textDelta:
            return .textDelta(index: index, delta: inner[Field.delta]?.string ?? "")
        case .textEnd:
            return .textEnded(index: index, content: inner[Field.content]?.string ?? "")
        case .thinkingDelta:
            return .thinkingDelta(index: index, delta: inner[Field.delta]?.string ?? "")
        case .thinkingEnd:
            return .thinkingEnded(index: index, content: inner[Field.content]?.string ?? "")
        case .toolCallStart:
            return .toolCallStarted(
                index: index,
                id: inner[Field.id]?.string ?? "",
                name: inner[Field.toolName]?.string ?? ""
            )
        case .toolCallEnd:
            guard let call = inner[Field.toolCall], let id = call[Field.id]?.string else { return nil }
            return .toolCallEnded(
                index: index,
                id: id,
                name: call[Field.name]?.string ?? "",
                argumentsJSON: call[Field.arguments]?.serialized ?? emptyArgumentsJSON
            )
        }
    }

    private static func decodeUIRequest(_ root: JSONValue) -> PiRPCRecord? {
        guard let id = root[Field.id]?.string,
              let methodName = root[Field.method]?.string,
              let method = UIMethod(rawValue: methodName)
        else { return nil }
        switch method {
        case .select, .confirm, .input, .editor:
            let dialogMethod: ConversationDialog.Method = switch method {
            case .select: .select
            case .confirm: .confirm
            case .input: .input
            default: .editor
            }
            return single(.dialogRequested(ConversationDialog(
                id: id,
                method: dialogMethod,
                title: root[Field.title]?.string,
                message: root[Field.message]?.string,
                options: strings(root[Field.options]),
                placeholder: root[Field.placeholder]?.string,
                prefill: root[Field.prefill]?.string,
                timeoutMs: root[Field.timeout]?.int
            )))
        case .notify:
            return single(.notified(message: root[Field.message]?.string ?? ""))
        case .setStatus:
            guard let key = root[Field.statusKey]?.string else { return nil }
            let text = root[Field.statusText]?.string.map(ANSIStripper.strip)
            return single(.statusChanged(key: key, text: text?.isEmpty == false ? text : nil))
        }
    }

    // MARK: Messages

    static func decodeMessage(_ value: JSONValue) -> ConversationMessage? {
        guard let roleName = value[Field.role]?.string else { return nil }
        let role = RoleName(rawValue: roleName).map(conversationRole) ?? .custom
        var message = ConversationMessage(role: role)
        if role == .toolResult {
            message.blocks = [.toolResult(
                toolCallID: value[Field.toolCallID]?.string ?? "",
                text: joinedText(value[Field.content]),
                isError: value[Field.isError]?.bool ?? false
            )]
        } else if role == .compactionSummary {
            let summary = value[Field.summary]?.string ?? ""
            message.blocks = summary.isEmpty ? [] : [.text(summary)]
        } else {
            message.blocks = decodeBlocks(value[Field.content])
        }
        message.timestamp = value[Field.timestamp]?.double.map { Date(timeIntervalSince1970: $0 / millisecondsPerSecond) }
        message.stopReason = value[Field.stopReason]?.string
        message.errorMessage = value[Field.errorMessage]?.string
        message.model = value[Field.model]?.string
        message.usage = value[Field.usage].map(decodeUsage)
        return message
    }

    private static func conversationRole(_ name: RoleName) -> ConversationRole {
        switch name {
        case .user: .user
        case .assistant: .assistant
        case .system: .system
        case .toolResult: .toolResult
        case .custom: .custom
        case .compactionSummary, .branchSummary: .compactionSummary
        }
    }

    private static func decodeBlocks(_ content: JSONValue?) -> [ConversationBlock] {
        if let text = content?.string {
            return text.isEmpty ? [] : [.text(text)]
        }
        return (content?.array ?? []).compactMap { block in
            guard let typeName = block[Field.type]?.string, let type = BlockType(rawValue: typeName) else { return nil }
            switch type {
            case .text:
                return .text(block[Field.text]?.string ?? "")
            case .thinking:
                return .thinking(block[Field.thinking]?.string ?? "")
            case .toolCall:
                return .toolCall(
                    id: block[Field.id]?.string ?? "",
                    name: block[Field.name]?.string ?? "",
                    argumentsJSON: block[Field.arguments]?.serialized ?? emptyArgumentsJSON
                )
            case .image:
                return .image(mimeType: block[Field.mimeType]?.string ?? "")
            }
        }
    }

    static func decodeUsage(_ value: JSONValue) -> ConversationUsage {
        ConversationUsage(
            input: value[Field.input]?.int ?? 0,
            output: value[Field.output]?.int ?? 0,
            cacheRead: value[Field.cacheRead]?.int ?? 0,
            cacheWrite: value[Field.cacheWrite]?.int ?? 0,
            reasoning: value[Field.reasoning]?.int ?? 0,
            total: value[Field.totalTokens]?.int ?? 0,
            cost: value[Field.cost]?[Field.total]?.double ?? 0
        )
    }

    /// Text blocks of a tool result joined; image blocks carry nothing to show.
    private static func joinedText(_ content: JSONValue?) -> String {
        if let text = content?.string { return text }
        return (content?.array ?? []).compactMap { block -> String? in
            guard let typeName = block[Field.type]?.string, BlockType(rawValue: typeName) == .text else { return nil }
            return block[Field.text]?.string
        }.joined(separator: textBlockSeparator)
    }

    private static func strings(_ value: JSONValue?) -> [String] {
        (value?.array ?? []).compactMap(\.string)
    }

    // MARK: Response payloads

    static func sessionInfo(from data: JSONValue?) -> ConversationSessionInfo? {
        guard let data, let sessionID = data[Field.sessionID]?.string else { return nil }
        return ConversationSessionInfo(
            sessionID: sessionID,
            sessionFile: data[Field.sessionFile]?.string,
            sessionName: data[Field.sessionName]?.string,
            modelID: data[Field.model]?[Field.id]?.string,
            provider: data[Field.model]?[Field.provider]?.string,
            thinkingLevel: data[Field.thinkingLevel]?.string,
            isStreaming: data[Field.isStreaming]?.bool ?? false,
            messageCount: data[Field.messageCount]?.int ?? 0
        )
    }

    static func stats(from data: JSONValue?) -> ConversationStats? {
        guard let data else { return nil }
        var stats = ConversationStats()
        if let tokens = data[Field.tokens] {
            stats.usage = ConversationUsage(
                input: tokens[Field.input]?.int ?? 0,
                output: tokens[Field.output]?.int ?? 0,
                cacheRead: tokens[Field.cacheRead]?.int ?? 0,
                cacheWrite: tokens[Field.cacheWrite]?.int ?? 0,
                total: tokens[Field.total]?.int ?? 0
            )
        }
        stats.usage.cost = data[Field.cost]?.double ?? 0
        stats.userMessages = data[Field.userMessages]?.int ?? 0
        stats.assistantMessages = data[Field.assistantMessages]?.int ?? 0
        stats.toolCalls = data[Field.toolCalls]?.int ?? 0
        stats.contextTokens = data[Field.contextUsage]?[Field.tokens]?.int
        stats.contextWindow = data[Field.contextUsage]?[Field.contextWindow]?.int
        stats.contextPercent = data[Field.contextUsage]?[Field.percent]?.double
        return stats
    }

    static func models(from data: JSONValue?) -> [ConversationModel] {
        (data?[Field.models]?.array ?? []).compactMap { model in
            guard let id = model[Field.id]?.string, let provider = model[Field.provider]?.string else { return nil }
            return ConversationModel(
                id: id,
                provider: provider,
                name: model[Field.name]?.string ?? id,
                reasoning: model[Field.reasoning]?.bool ?? false,
                acceptsImages: strings(model[Field.input]).contains(imageModality),
                contextWindow: model[Field.contextWindow]?.int
            )
        }
    }

    static func commands(from data: JSONValue?) -> [ConversationCommand] {
        (data?[Field.commands]?.array ?? []).compactMap { command in
            guard let name = command[Field.name]?.string else { return nil }
            return ConversationCommand(
                name: name,
                description: command[Field.description]?.string,
                source: command[Field.source]?.string ?? ""
            )
        }
    }

    static func thinkingLevels(from data: JSONValue?) -> [String] {
        strings(data?[Field.levels])
    }

    static func messages(from data: JSONValue?) -> [ConversationMessage] {
        (data?[Field.messages]?.array ?? []).compactMap(decodeMessage)
    }

    static func queue(from data: JSONValue?) -> (steering: [String], followUp: [String]) {
        (strings(data?[Field.steering]), strings(data?[Field.followUp]))
    }

    /// A prompt accepted without a disposition started a run.
    static func disposition(from data: JSONValue?) -> PromptDisposition {
        data?[Field.disposition]?.string.flatMap(PromptDisposition.init(rawValue:)) ?? .started
    }
}
