import Foundation

enum ConversationRole: Equatable, Sendable {
    case user
    case assistant
    case system
    case toolResult
    case custom
    /// A compaction or branch summary Pi stores in the history in place of the folded messages.
    case compactionSummary
}

enum ConversationStopReason {
    static let aborted = "aborted"
    static let error = "error"
}

enum ConversationBlock: Equatable, Sendable {
    case text(String)
    case thinking(String)
    case toolCall(id: String, name: String, argumentsJSON: String)
    /// Image data is not kept in the timeline.
    case image(mimeType: String)
    case toolResult(toolCallID: String, text: String, isError: Bool)
}

struct ConversationUsage: Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var reasoning = 0
    var total = 0
    var cost = 0.0

    static let zero = ConversationUsage()

    static func + (lhs: ConversationUsage, rhs: ConversationUsage) -> ConversationUsage {
        ConversationUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            reasoning: lhs.reasoning + rhs.reasoning,
            total: lhs.total + rhs.total,
            cost: lhs.cost + rhs.cost
        )
    }
}

struct ConversationMessage: Equatable, Sendable {
    var role: ConversationRole
    var blocks: [ConversationBlock] = []
    var timestamp: Date?
    var stopReason: String?
    var errorMessage: String?
    var usage: ConversationUsage?
    var model: String?
}

struct ConversationDialog: Equatable, Sendable {
    enum Method: Equatable, Sendable {
        case select
        case confirm
        case input
        case editor
    }

    let id: String
    var method: Method
    var title: String?
    var message: String?
    var options: [String] = []
    var placeholder: String?
    var prefill: String?
    /// Milliseconds after which Pi resolves the request on its own side.
    var timeoutMs: Int?
}

enum ConversationDialogAnswer: Equatable, Sendable {
    case value(String)
    case confirmed(Bool)
    case cancelled
}

/// Agent-neutral events a driver feeds into `ConversationReducer`.
enum ConversationEvent: Equatable, Sendable {
    case runStarted
    case runSettled(aborted: Bool)
    case turnStarted
    case turnEnded
    case messageStarted(role: ConversationRole)
    case textDelta(index: Int, delta: String)
    case textEnded(index: Int, content: String)
    case thinkingDelta(index: Int, delta: String)
    case thinkingEnded(index: Int, content: String)
    case toolCallStarted(index: Int, id: String, name: String)
    case toolCallEnded(index: Int, id: String, name: String, argumentsJSON: String)
    case messageEnded(ConversationMessage)
    /// Cumulative for the current assistant message.
    case usageUpdated(ConversationUsage)
    case toolExecutionStarted(id: String, name: String, argumentsJSON: String)
    case toolExecutionEnded(id: String, name: String, resultText: String, isError: Bool, durationMs: Int?)
    case queueChanged(steering: [String], followUp: [String])
    case compactionStarted(reason: String)
    case compactionEnded(summary: String?, aborted: Bool, errorMessage: String?)
    case retryScheduled(attempt: Int, maxAttempts: Int, errorMessage: String)
    case retryFinished(success: Bool, finalError: String?)
    case dialogRequested(ConversationDialog)
    case notified(message: String)
    case statusChanged(key: String, text: String?)
    case thinkingLevelChanged(String)
    case sessionNameChanged(String?)
    case extensionError(String)
}
