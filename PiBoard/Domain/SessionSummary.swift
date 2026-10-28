import Foundation

/// What a task's agent session looks like from the outside: enough for a card and an inspector
/// row, read from the session file without replaying the conversation.
struct SessionSummary: Equatable, Sendable {
    struct Usage: Equatable, Sendable {
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0
        var total = 0
        var cost = 0.0

        static func + (lhs: Usage, rhs: Usage) -> Usage {
            Usage(
                input: lhs.input + rhs.input,
                output: lhs.output + rhs.output,
                cacheRead: lhs.cacheRead + rhs.cacheRead,
                cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
                total: lhs.total + rhs.total,
                cost: lhs.cost + rhs.cost
            )
        }
    }

    var name: String?
    /// Text of the latest assistant message that said anything; tool-only turns are skipped.
    var lastAssistantText: String?
    /// User prompts, which is what a person means by "turns".
    var turnCount = 0
    var assistantMessageCount = 0
    /// Last `model_change`, else the model named by the latest assistant message.
    var model: String?
    var usage = Usage()
    /// Newest entry timestamp in the file.
    var lastActivity: Date?

    var firstLineOfLastMessage: String? {
        lastAssistantText?
            .split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}
