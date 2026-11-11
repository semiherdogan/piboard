import Foundation

struct ToolCallItem: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case running
        case finished
    }

    var callID: String
    var name: String
    var argumentsJSON: String
    var resultText: String?
    var isError = false
    var durationMs: Int?
    var status = Status.running
}

/// One entry of the timeline a chat view renders.
struct ConversationItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case user(text: String, imageCount: Int)
        case assistant(text: String)
        case thinking(text: String)
        case toolCall(ToolCallItem)
        case compaction(summary: String?)
        case notice(text: String)
    }

    let id: UUID
    var kind: Kind
    /// True while the item is still being appended to.
    var isStreaming: Bool
    /// When the item first appeared; the "Worked for" row measures a turn from these.
    let createdAt: Date

    init(id: UUID = UUID(), kind: Kind, isStreaming: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.isStreaming = isStreaming
        self.createdAt = createdAt
    }
}
