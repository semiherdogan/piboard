import Foundation
import Testing
@testable import PiBoard

struct ConversationLiveStatusTests {
    private static func streamingState() -> ConversationState {
        var state = ConversationState()
        ConversationReducer.apply(.runStarted, to: &state)
        ConversationReducer.apply(.messageStarted(role: .assistant), to: &state)
        ConversationReducer.apply(.textDelta(index: 0, delta: "a"), to: &state)
        return state
    }

    @Test func aStreamedDeltaDoesNotChangeTheStatus() {
        var state = Self.streamingState()
        let before = ConversationLiveStatus(state)
        ConversationReducer.apply(.textDelta(index: 0, delta: "b"), to: &state)

        #expect(ConversationLiveStatus(state) == before)
        #expect(state.items.last?.kind == .assistant(text: "ab"))
    }

    @Test func runStateAndQueueChangeTheStatus() {
        var state = Self.streamingState()
        let running = ConversationLiveStatus(state)
        #expect(running.isRunning)
        #expect(running.agentActivity == .working)

        ConversationReducer.apply(.queueChanged(steering: ["a"], followUp: ["b"]), to: &state)
        #expect(ConversationLiveStatus(state).queuedMessages == ["a", "b"])

        ConversationReducer.apply(.runSettled(aborted: false), to: &state)
        #expect(!ConversationLiveStatus(state).isRunning)
    }

    @Test func aDialogChangesTheStatus() {
        var state = ConversationState()
        let dialog = ConversationDialog(id: "1", method: .confirm)
        ConversationReducer.apply(.dialogRequested(dialog), to: &state)

        let status = ConversationLiveStatus(state)
        #expect(status.pendingDialog == dialog)
        #expect(status.agentActivity == .needsInput)
    }
}
