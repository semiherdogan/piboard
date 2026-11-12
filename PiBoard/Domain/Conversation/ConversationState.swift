import Foundation

struct ConversationState: Equatable, Sendable {
    var items: [ConversationItem] = []
    var isRunning = false
    /// FIFO: Pi can open a second request before the first is answered.
    var pendingDialogs: [ConversationDialog] = []
    var steeringQueue: [String] = []
    var followUpQueue: [String] = []
    var thinkingLevel: String?
    var sessionName: String?
    /// Session total: the sum of every assistant message's usage.
    var usage = ConversationUsage.zero
    var lastUsage: ConversationUsage?
    /// Extension status bar text by key.
    var statuses: [String: String] = [:]
    /// The primary agent an extension selected; nil when none or cleared.
    var activeAgentName: String?
    /// Content block index to the item the open assistant message streams into; reducer bookkeeping.
    var streamingIndexes: [Int: UUID] = [:]

    var pendingDialog: ConversationDialog? { pendingDialogs.first }

    var agentActivity: AgentActivity {
        if !pendingDialogs.isEmpty { return .needsInput }
        return isRunning ? .working : .idle
    }

    mutating func dialogAnswered(id: String) {
        pendingDialogs.removeAll { $0.id == id }
    }

    /// Rebuilds the timeline from stored history (resume).
    mutating func load(messages: [ConversationMessage]) {
        items = []
        usage = .zero
        lastUsage = nil
        streamingIndexes = [:]
        for message in messages {
            ConversationReducer.apply(.messageEnded(message), to: &self) { message.timestamp ?? Date() }
        }
        ConversationReducer.finishRunningToolCalls(in: &self)
    }
}
