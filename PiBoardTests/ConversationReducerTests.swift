import Foundation
import Testing
@testable import PiBoard

struct ConversationReducerTests {
    private func reduce(_ events: [ConversationEvent], from start: ConversationState = ConversationState()) -> ConversationState {
        var state = start
        for event in events {
            ConversationReducer.apply(event, to: &state)
        }
        return state
    }

    private func kinds(_ state: ConversationState) -> [ConversationItem.Kind] {
        state.items.map(\.kind)
    }

    private func usage(input: Int, output: Int, cost: Double) -> ConversationUsage {
        ConversationUsage(input: input, output: output, total: input + output, cost: cost)
    }

    private func userMessage(_ text: String) -> ConversationMessage {
        ConversationMessage(role: .user, blocks: [.text(text)])
    }

    private func assistantMessage(_ blocks: [ConversationBlock], usage: ConversationUsage? = nil) -> ConversationMessage {
        ConversationMessage(role: .assistant, blocks: blocks, usage: usage)
    }

    private func call(
        _ id: String,
        name: String = "read",
        arguments: String = "{}",
        result: String? = nil,
        isError: Bool = false
    ) -> ConversationItem.Kind {
        .toolCall(ToolCallItem(
            callID: id,
            name: name,
            argumentsJSON: arguments,
            resultText: result,
            isError: isError,
            status: .finished
        ))
    }

    @Test func plainTurn() {
        let first = usage(input: 100, output: 5, cost: 0.5)
        var state = reduce([
            .runStarted,
            .turnStarted,
            .messageStarted(role: .user),
            .messageEnded(userMessage("ping")),
            .messageStarted(role: .assistant),
            .textDelta(index: 0, delta: "po"),
            .textDelta(index: 0, delta: "ng!"),
        ])
        #expect(state.isRunning)
        #expect(state.agentActivity == .working)
        #expect(kinds(state) == [.user(text: "ping", imageCount: 0), .assistant(text: "pong!")])
        #expect(state.items[1].isStreaming)

        for event: ConversationEvent in [
            .textEnded(index: 0, content: "pong"),
            .messageEnded(assistantMessage([.text("pong")], usage: first)),
            .turnEnded,
            .runSettled(aborted: false),
        ] {
            ConversationReducer.apply(event, to: &state)
        }

        #expect(kinds(state) == [.user(text: "ping", imageCount: 0), .assistant(text: "pong")])
        #expect(state.items.allSatisfy { !$0.isStreaming })
        #expect(state.usage == first)
        #expect(state.lastUsage == first)
        #expect(!state.isRunning)
        #expect(state.agentActivity == .idle)
    }

    @Test func messageEndedIsAuthoritativeOverStreamedText() {
        let state = reduce([
            .messageStarted(role: .assistant),
            .textDelta(index: 0, delta: "partial"),
            .messageEnded(assistantMessage([.text("final")])),
        ])

        #expect(kinds(state) == [.assistant(text: "final")])
    }

    @Test func usageSumsAcrossAssistantMessages() {
        let one = usage(input: 10, output: 1, cost: 0.25)
        let two = usage(input: 20, output: 2, cost: 0.5)
        let state = reduce([
            .messageEnded(assistantMessage([.text("a")], usage: one)),
            .usageUpdated(usage(input: 5, output: 0, cost: 0)),
            .messageEnded(assistantMessage([.text("b")], usage: two)),
        ])

        #expect(state.usage == one + two)
        #expect(state.lastUsage == two)
    }

    @Test func thinkingAndTextMessage() {
        let state = reduce([
            .messageStarted(role: .assistant),
            .thinkingDelta(index: 0, delta: "hm"),
            .thinkingDelta(index: 0, delta: "m"),
            .thinkingEnded(index: 0, content: "hmm"),
            .textDelta(index: 1, delta: "Done"),
            .textEnded(index: 1, content: "Done."),
            .messageEnded(assistantMessage([.thinking("hmm"), .text("Done.")])),
            .runSettled(aborted: false),
        ])

        #expect(kinds(state) == [.thinking(text: "hmm"), .assistant(text: "Done.")])
    }

    @Test func toolTurn() {
        let args = #"{"path":"README.md"}"#
        let state = reduce([
            .runStarted,
            .messageEnded(userMessage("read it")),
            .messageStarted(role: .assistant),
            .toolCallStarted(index: 0, id: "c1", name: "read"),
            .toolCallEnded(index: 0, id: "c1", name: "read", argumentsJSON: args),
            .messageEnded(assistantMessage([.toolCall(id: "c1", name: "read", argumentsJSON: args)])),
            .toolExecutionStarted(id: "c1", name: "read", argumentsJSON: args),
            .toolExecutionEnded(id: "c1", name: "read", resultText: "contents", isError: false, durationMs: 12),
            .messageEnded(ConversationMessage(role: .toolResult, blocks: [.toolResult(toolCallID: "c1", text: "contents", isError: false)])),
            .messageStarted(role: .assistant),
            .textDelta(index: 0, delta: "It says hi"),
            .messageEnded(assistantMessage([.text("It says hi")])),
            .runSettled(aborted: false),
        ])

        #expect(state.items.count == 3)
        guard case .toolCall(let item) = state.items[1].kind else {
            Issue.record("expected a tool call item")
            return
        }
        #expect(item.callID == "c1")
        #expect(item.argumentsJSON == args)
        #expect(item.resultText == "contents")
        #expect(item.durationMs == 12)
        #expect(item.status == .finished)
        #expect(state.items[2].kind == .assistant(text: "It says hi"))
    }

    @Test func toolExecutionMarksARunningCall() {
        let state = reduce([
            .messageStarted(role: .assistant),
            .toolCallEnded(index: 0, id: "c1", name: "bash", argumentsJSON: "{}"),
            .messageEnded(assistantMessage([.toolCall(id: "c1", name: "bash", argumentsJSON: "{}")])),
            .toolExecutionStarted(id: "c1", name: "bash", argumentsJSON: "{}"),
        ])

        guard case .toolCall(let item) = state.items[0].kind else {
            Issue.record("expected a tool call item")
            return
        }
        #expect(item.status == .running)
    }

    @Test func toolResultMessageAttachesWhenExecutionEndWasNotSeen() {
        let state = reduce([
            .messageEnded(assistantMessage([.toolCall(id: "c1", name: "read", argumentsJSON: "{}")])),
            .messageEnded(ConversationMessage(role: .toolResult, blocks: [.toolResult(toolCallID: "c1", text: "boom", isError: true)])),
        ])

        #expect(kinds(state) == [call("c1", result: "boom", isError: true)])
    }

    @Test func abortKeepsPartialTextAndFinishesStreaming() {
        let state = reduce([
            .runStarted,
            .messageStarted(role: .assistant),
            .textDelta(index: 0, delta: "1, 2, "),
            .runSettled(aborted: true),
        ])

        #expect(kinds(state) == [.assistant(text: "1, 2, ")])
        #expect(!state.items[0].isStreaming)
        #expect(!state.isRunning)
    }

    @Test func steerQueueFillsAndDrains() {
        let state = reduce([.runStarted, .queueChanged(steering: ["stop"], followUp: ["later"])])
        #expect(state.steeringQueue == ["stop"])
        #expect(state.followUpQueue == ["later"])

        let drained = reduce([.queueChanged(steering: [], followUp: [])], from: state)
        #expect(drained.steeringQueue.isEmpty)
        #expect(drained.followUpQueue.isEmpty)
    }

    @Test func dialogGivesNeedsInputThenWorking() {
        let dialog = ConversationDialog(id: "d1", method: .confirm, title: "Spike", message: "Proceed?")
        var state = reduce([.runStarted, .dialogRequested(dialog)])

        #expect(state.pendingDialog == dialog)
        #expect(state.agentActivity == .needsInput)

        state.dialogAnswered(id: dialog.id)

        #expect(state.pendingDialog == nil)
        #expect(state.agentActivity == .working)
    }

    @Test func aSettledRunDropsItsPendingDialogs() {
        let state = reduce([.dialogRequested(ConversationDialog(id: "d1", method: .confirm)), .runSettled(aborted: true)])

        #expect(state.pendingDialogs.isEmpty)
        #expect(state.agentActivity == .idle)
    }

    @Test func dialogsQueueInOrder() {
        let first = ConversationDialog(id: "d1", method: .confirm, title: "One")
        let second = ConversationDialog(id: "d2", method: .input, title: "Two")
        var state = reduce([.dialogRequested(first), .dialogRequested(second)])

        #expect(state.pendingDialogs == [first, second])
        #expect(state.pendingDialog == first)

        state.dialogAnswered(id: first.id)

        #expect(state.pendingDialog == second)
        #expect(state.agentActivity == .needsInput)
    }

    @Test func anAssistantErrorBecomesANoticeAfterItsBlocks() {
        let failed = ConversationMessage(role: .assistant, stopReason: ConversationStopReason.error, errorMessage: "401")
        let state = reduce([.messageStarted(role: .assistant), .messageEnded(failed)])
        #expect(kinds(state) == [.notice(text: "401")])

        let partial = ConversationMessage(
            role: .assistant,
            blocks: [.text("half")],
            stopReason: ConversationStopReason.error,
            errorMessage: "overloaded"
        )
        #expect(kinds(reduce([.messageEnded(partial)])) == [.assistant(text: "half"), .notice(text: "overloaded")])
    }

    @Test func anAbortedAssistantMessageAddsNoErrorNotice() {
        let aborted = ConversationMessage(
            role: .assistant,
            blocks: [.text("half")],
            stopReason: ConversationStopReason.aborted,
            errorMessage: "Request was aborted"
        )
        #expect(kinds(reduce([.messageEnded(aborted)])) == [.assistant(text: "half")])
    }

    @Test func compactionSummaryMessagesBecomeCompactionItems() {
        let summary = ConversationMessage(role: .compactionSummary, blocks: [.text("folded")])

        #expect(kinds(reduce([.messageEnded(summary)])) == [.compaction(summary: "folded")])

        var loaded = ConversationState()
        loaded.load(messages: [userMessage("hi"), summary])
        #expect(kinds(loaded) == [.user(text: "hi", imageCount: 0), .compaction(summary: "folded")])
    }

    @Test func statusWithNilTextRemovesTheKey() {
        let set = reduce([.statusChanged(key: "usage", text: "42%")])
        #expect(set.statuses == ["usage": "42%"])

        let cleared = reduce([.statusChanged(key: "usage", text: nil)], from: set)
        #expect(cleared.statuses.isEmpty)
    }

    @Test func activeAgentEventSetsAndClearsTheName() {
        let set = reduce([.activeAgentChanged("architect")])
        #expect(set.activeAgentName == "architect")
        #expect(reduce([.activeAgentChanged(nil)], from: set).activeAgentName == nil)
    }

    @Test func loadingHistoryKeepsTheActiveAgent() {
        var state = reduce([.activeAgentChanged("architect")])
        state.load(messages: [ConversationMessage(role: .custom)])
        #expect(state.activeAgentName == "architect")
        #expect(state.items.isEmpty)
    }

    @Test func liveStatusCarriesAgentAndStatuses() {
        let state = reduce([.activeAgentChanged("architect"), .statusChanged(key: "usage", text: "42%")])
        let status = ConversationLiveStatus(state)
        #expect(status.activeAgentName == "architect")
        #expect(status.statuses == ["usage": "42%"])
    }

    @Test func scalarEventsUpdateTheState() {
        let state = reduce([
            .thinkingLevelChanged("high"),
            .sessionNameChanged("Fix login"),
        ])

        #expect(state.thinkingLevel == "high")
        #expect(state.sessionName == "Fix login")
        #expect(reduce([.sessionNameChanged(nil)], from: state).sessionName == nil)
    }

    @Test func noticesAndCompactionAppendItems() {
        let state = reduce([
            .notified(message: "hello"),
            .extensionError("bad"),
            .retryScheduled(attempt: 1, maxAttempts: 3, errorMessage: "overloaded"),
            .compactionStarted(reason: "threshold"),
            .compactionEnded(summary: "short", aborted: false, errorMessage: nil),
        ])

        #expect(state.items.count == 4)
        #expect(state.items[0].kind == .notice(text: "hello"))
        #expect(state.items[3].kind == .compaction(summary: "short"))
    }

    @Test func systemAndCustomMessagesAddNothing() {
        let state = reduce([
            .messageEnded(ConversationMessage(role: .system, blocks: [.text("sys")])),
            .messageEnded(ConversationMessage(role: .custom, blocks: [.text("custom")])),
        ])

        #expect(state.items.isEmpty)
    }

    @Test func userMessageCountsImagesAndJoinsText() {
        let state = reduce([
            .messageEnded(ConversationMessage(role: .user, blocks: [.text("look"), .image(mimeType: "image/png"), .text("here")])),
        ])

        #expect(kinds(state) == [.user(text: "look\nhere", imageCount: 1)])
    }

    @Test func loadRebuildsTheSameItemsAsTheLivePath() {
        let args = #"{"path":"a"}"#
        let first = usage(input: 10, output: 2, cost: 0.1)
        let second = usage(input: 20, output: 3, cost: 0.2)
        let messages = [
            userMessage("do it"),
            assistantMessage([.thinking("plan"), .text("Reading"), .toolCall(id: "c1", name: "read", argumentsJSON: args)], usage: first),
            ConversationMessage(role: .toolResult, blocks: [.toolResult(toolCallID: "c1", text: "data", isError: false)]),
            assistantMessage([.text("Done")], usage: second),
        ]
        let live = reduce([
            .runStarted,
            .messageEnded(messages[0]),
            .messageStarted(role: .assistant),
            .thinkingDelta(index: 0, delta: "pl"),
            .textDelta(index: 1, delta: "Read"),
            .toolCallStarted(index: 2, id: "c1", name: "read"),
            .toolCallEnded(index: 2, id: "c1", name: "read", argumentsJSON: args),
            .messageEnded(messages[1]),
            .toolExecutionStarted(id: "c1", name: "read", argumentsJSON: args),
            .toolExecutionEnded(id: "c1", name: "read", resultText: "data", isError: false, durationMs: nil),
            .messageEnded(messages[2]),
            .messageStarted(role: .assistant),
            .textDelta(index: 0, delta: "Do"),
            .messageEnded(messages[3]),
            .runSettled(aborted: false),
        ])

        var loaded = ConversationState()
        loaded.load(messages: messages)

        #expect(kinds(loaded) == kinds(live))
        #expect(loaded.usage == first + second)
        #expect(loaded.usage == live.usage)
        #expect(loaded.items.count == 5)
    }

    @Test func loadFinishesACallThatNeverGotAResult() {
        var state = ConversationState()
        state.load(messages: [assistantMessage([.toolCall(id: "c1", name: "bash", argumentsJSON: "{}")])])

        #expect(kinds(state) == [call("c1", name: "bash")])
    }
}
