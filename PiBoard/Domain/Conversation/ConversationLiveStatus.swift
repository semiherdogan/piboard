import Foundation

/// The parts of `ConversationState` that change rarely, so a view reading them is not invalidated by every streamed delta.
struct ConversationLiveStatus: Equatable, Sendable {
    var isRunning = false
    var thinkingLevel: String?
    var usage = ConversationUsage.zero
    var agentActivity = AgentActivity.idle
    var pendingDialog: ConversationDialog?
    var queuedMessages: [String] = []

    init() {}

    init(_ state: ConversationState) {
        isRunning = state.isRunning
        thinkingLevel = state.thinkingLevel
        usage = state.usage
        agentActivity = state.agentActivity
        pendingDialog = state.pendingDialog
        queuedMessages = state.steeringQueue + state.followUpQueue
    }
}
