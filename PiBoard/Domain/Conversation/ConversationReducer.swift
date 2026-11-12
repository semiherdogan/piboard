import Foundation

enum ConversationReducer {
    private static let userTextSeparator = "\n"
    private static let extensionErrorPrefix = "Extension error: "
    private static let compactionCancelledNotice = "Compaction was cancelled"
    private static let retrySucceededNotice = "Retry succeeded"
    private static let unknownErrorText = "unknown error"

    static func apply(_ event: ConversationEvent, to state: inout ConversationState, now: () -> Date = Date.init) {
        switch event {
        case .runStarted:
            state.isRunning = true
        case .runSettled:
            settleRun(in: &state)
        case .turnStarted, .turnEnded, .compactionStarted:
            break
        case .messageStarted(let role):
            if role == .assistant { openAssistantGroup(in: &state) }
        case .textDelta(let index, let delta):
            write(index: index, streaming: true, to: &state, now: now) { existing in
                if case .assistant(let text) = existing { return .assistant(text: text + delta) }
                return .assistant(text: delta)
            }
        case .textEnded(let index, let content):
            write(index: index, streaming: false, to: &state, now: now) { _ in .assistant(text: content) }
        case .thinkingDelta(let index, let delta):
            write(index: index, streaming: true, to: &state, now: now) { existing in
                if case .thinking(let text) = existing { return .thinking(text: text + delta) }
                return .thinking(text: delta)
            }
        case .thinkingEnded(let index, let content):
            write(index: index, streaming: false, to: &state, now: now) { _ in .thinking(text: content) }
        case .toolCallStarted(let index, let id, let name):
            write(index: index, streaming: true, to: &state, now: now) { _ in
                .toolCall(ToolCallItem(callID: id, name: name, argumentsJSON: ""))
            }
        case .toolCallEnded(let index, let id, let name, let argumentsJSON):
            write(index: index, streaming: false, to: &state, now: now) { _ in
                .toolCall(ToolCallItem(callID: id, name: name, argumentsJSON: argumentsJSON))
            }
        case .messageEnded(let message):
            endMessage(message, in: &state, now: now)
        case .usageUpdated(let usage):
            state.lastUsage = usage
        case .toolExecutionStarted(let id, let name, let argumentsJSON):
            updateToolCall(
                callID: id,
                creating: ToolCallItem(callID: id, name: name, argumentsJSON: argumentsJSON),
                in: &state,
                now: now
            ) { $0.status = .running }
        case .toolExecutionEnded(let id, let name, let resultText, let isError, let durationMs):
            updateToolCall(
                callID: id,
                creating: ToolCallItem(callID: id, name: name, argumentsJSON: ""),
                in: &state,
                now: now
            ) {
                $0.resultText = resultText
                $0.isError = isError
                $0.durationMs = durationMs
                $0.status = .finished
            }
        case .queueChanged(let steering, let followUp):
            state.steeringQueue = steering
            state.followUpQueue = followUp
        case .compactionEnded(let summary, let aborted, let errorMessage):
            if aborted || errorMessage != nil {
                state.items.append(ConversationItem(kind: .notice(text: errorMessage ?? compactionCancelledNotice), createdAt: now()))
            } else {
                state.items.append(ConversationItem(kind: .compaction(summary: summary), createdAt: now()))
            }
        case .retryScheduled(let attempt, let maxAttempts, let errorMessage):
            appendNotice("Retrying (\(attempt)/\(maxAttempts)): \(errorMessage)", to: &state, now: now)
        case .retryFinished(let success, let finalError):
            appendNotice(success ? retrySucceededNotice : "Retry failed: \(finalError ?? unknownErrorText)", to: &state, now: now)
        case .dialogRequested(let dialog):
            state.pendingDialogs.append(dialog)
        case .notified(let message):
            appendNotice(message, to: &state, now: now)
        case .statusChanged(let key, let text):
            state.statuses[key] = text
        case .activeAgentChanged(let name):
            state.activeAgentName = name
        case .thinkingLevelChanged(let level):
            state.thinkingLevel = level
        case .sessionNameChanged(let name):
            state.sessionName = name
        case .extensionError(let message):
            appendNotice(extensionErrorPrefix + message, to: &state, now: now)
        }
    }

    /// A call that never got a result (aborted run, truncated history) must not spin forever.
    static func finishRunningToolCalls(in state: inout ConversationState) {
        for position in state.items.indices {
            guard case .toolCall(var call) = state.items[position].kind, call.status == .running else { continue }
            call.status = .finished
            state.items[position].kind = .toolCall(call)
        }
    }

    private static func settleRun(in state: inout ConversationState) {
        state.isRunning = false
        // Pi resolves open dialogs silently when the run's abort signal fires, so none can outlive the run.
        state.pendingDialogs = []
        state.streamingIndexes = [:]
        for position in state.items.indices {
            state.items[position].isStreaming = false
        }
        finishRunningToolCalls(in: &state)
    }

    private static func openAssistantGroup(in state: inout ConversationState) {
        state.streamingIndexes = [:]
    }

    private static func appendNotice(_ text: String, to state: inout ConversationState, now: () -> Date) {
        state.items.append(ConversationItem(kind: .notice(text: text), createdAt: now()))
    }

    /// Updates the item streaming at `index`, or appends one on the first event for that index.
    private static func write(
        index: Int,
        streaming: Bool,
        to state: inout ConversationState,
        now: () -> Date,
        _ transform: (ConversationItem.Kind?) -> ConversationItem.Kind
    ) {
        if let id = state.streamingIndexes[index], let position = state.items.firstIndex(where: { $0.id == id }) {
            state.items[position].kind = transform(state.items[position].kind)
            state.items[position].isStreaming = streaming
        } else {
            let item = ConversationItem(kind: transform(nil), isStreaming: streaming, createdAt: now())
            state.items.append(item)
            state.streamingIndexes[index] = item.id
        }
    }

    private static func updateToolCall(
        callID: String,
        creating fallback: ToolCallItem,
        in state: inout ConversationState,
        now: () -> Date,
        _ mutate: (inout ToolCallItem) -> Void
    ) {
        let position = state.items.lastIndex { item in
            if case .toolCall(let call) = item.kind { return call.callID == callID }
            return false
        }
        guard let position, case .toolCall(var call) = state.items[position].kind else {
            var call = fallback
            mutate(&call)
            state.items.append(ConversationItem(kind: .toolCall(call), createdAt: now()))
            return
        }
        mutate(&call)
        state.items[position].kind = .toolCall(call)
    }

    private static func endMessage(_ message: ConversationMessage, in state: inout ConversationState, now: () -> Date) {
        switch message.role {
        case .assistant:
            replaceStreamingGroup(with: message, in: &state, now: now)
            if let errorMessage = message.errorMessage, message.stopReason != ConversationStopReason.aborted {
                appendNotice(errorMessage, to: &state, now: now)
            }
            if let usage = message.usage {
                state.usage = state.usage + usage
                state.lastUsage = usage
            }
        case .user:
            let texts = message.blocks.compactMap { block -> String? in
                if case .text(let text) = block { return text }
                return nil
            }
            let imageCount = message.blocks.filter { block in
                if case .image = block { return true }
                return false
            }.count
            state.items.append(ConversationItem(kind: .user(
                text: texts.joined(separator: userTextSeparator),
                imageCount: imageCount
            ), createdAt: now()))
        case .toolResult:
            for case .toolResult(let callID, let text, let isError) in message.blocks {
                attachResult(callID: callID, text: text, isError: isError, to: &state)
            }
        case .compactionSummary:
            let summary = message.blocks.compactMap { block -> String? in
                if case .text(let text) = block { return text }
                return nil
            }.joined(separator: userTextSeparator)
            state.items.append(ConversationItem(kind: .compaction(summary: summary.isEmpty ? nil : summary), createdAt: now()))
        case .system, .custom:
            break
        }
    }

    private static func attachResult(callID: String, text: String, isError: Bool, to state: inout ConversationState) {
        guard let position = state.items.lastIndex(where: { item in
            if case .toolCall(let call) = item.kind { return call.callID == callID }
            return false
        }), case .toolCall(var call) = state.items[position].kind, call.resultText == nil else { return }
        call.resultText = text
        call.isError = isError
        call.status = .finished
        state.items[position].kind = .toolCall(call)
    }

    private static func replaceStreamingGroup(with message: ConversationMessage, in state: inout ConversationState, now: () -> Date) {
        let groupIDs = Set(state.streamingIndexes.values)
        let groupPositions = state.items.indices.filter { groupIDs.contains(state.items[$0].id) }
        let streamedStarts = Dictionary(uniqueKeysWithValues: groupPositions.map { (state.items[$0].id, state.items[$0].createdAt) })
        let insertAt = groupPositions.first ?? state.items.count
        for position in groupPositions.reversed() {
            state.items.remove(at: position)
        }
        var replacement: [ConversationItem] = []
        for (index, block) in message.blocks.enumerated() {
            let kind: ConversationItem.Kind
            switch block {
            case .text(let text):
                guard !text.isEmpty else { continue }
                kind = .assistant(text: text)
            case .thinking(let text):
                guard !text.isEmpty else { continue }
                kind = .thinking(text: text)
            case .toolCall(let id, let name, let argumentsJSON):
                kind = .toolCall(ToolCallItem(callID: id, name: name, argumentsJSON: argumentsJSON))
            case .image, .toolResult:
                continue
            }
            // Reusing the streamed item's id keeps the row stable in the view, and its start time keeps the turn's duration.
            let streamedID = state.streamingIndexes[index]
            replacement.append(ConversationItem(
                id: streamedID ?? UUID(),
                kind: kind,
                createdAt: streamedID.flatMap { streamedStarts[$0] } ?? now()
            ))
        }
        state.items.insert(contentsOf: replacement, at: insertAt)
        state.streamingIndexes = [:]
    }
}
