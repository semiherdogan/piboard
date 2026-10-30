import Foundation

/// What a task hands to its next agent: the task, the conversation so far and the files touched.
struct SessionHandoff: Equatable, Sendable {
    let sourceAgent: AgentKind
    let taskTitle: String
    let taskPrompt: String
    let transcript: SessionTranscript
}

struct SessionHandoffOptions: Equatable, Sendable {
    var includeAssistantReplies = true
    var includeChangedFiles = true
    var maxTurns = SessionHandoffRenderer.defaultMaxTurns
}

enum SessionHandoffRenderer {
    static let defaultMaxTurns = 20
    static let maxMessageCharacters = 4_000
    static let maxTotalBytes = 48 * 1024

    static let titlePrefix = "# Handoff from "
    static let introPrefix = "This task was started with "
    static let introSuffix = ". Continue it from where that session stopped. Read the changed files before editing them; the previous agent's context is not available to you."
    static let taskHeading = "## Task"
    static let promptHeading = "## Original prompt"
    static let conversationHeading = "## Conversation"
    static let changedFilesHeading = "## Changed files"
    static let userLabel = "**User:** "
    static let assistantLabel = "**Assistant:** "
    static let noConversationLine = "No conversation was recorded."
    static let clippedMarker = "... (clipped)"
    static let fileBullet = "- "

    private static let blockSeparator = "\n\n"
    private static let lineSeparator = "\n"
    private static let minimumKeptTurns = 1

    /// One user message with the assistant messages that follow it. Assistant messages before the
    /// first user message belong to a turn of their own with no user text.
    private struct Turn {
        var user: String?
        var assistant: [String] = []
    }

    static func render(_ handoff: SessionHandoff, options: SessionHandoffOptions) -> String {
        let turns = makeTurns(handoff.transcript.messages)
        let keepCount = min(turns.count, max(options.maxTurns, minimumKeptTurns))
        var kept = Array(turns.suffix(keepCount))
        var document = compose(handoff, options: options, turns: kept, totalTurns: turns.count)
        // Whole turns go oldest first; the last turn stays even when it alone is too large.
        while document.utf8.count > maxTotalBytes, kept.count > minimumKeptTurns {
            kept.removeFirst()
            document = compose(handoff, options: options, turns: kept, totalTurns: turns.count)
        }
        return document
    }

    private static func makeTurns(_ messages: [SessionTranscript.Message]) -> [Turn] {
        var turns: [Turn] = []
        for message in messages {
            switch message.role {
            case .user:
                turns.append(Turn(user: message.text))
            case .assistant:
                if turns.isEmpty {
                    turns.append(Turn())
                }
                turns[turns.count - 1].assistant.append(message.text)
            }
        }
        return turns
    }

    private static func compose(
        _ handoff: SessionHandoff,
        options: SessionHandoffOptions,
        turns: [Turn],
        totalTurns: Int
    ) -> String {
        let source = handoff.sourceAgent.title
        var blocks = [
            titlePrefix + source,
            introPrefix + source + introSuffix,
            taskHeading,
            handoff.taskTitle,
            promptHeading,
            handoff.taskPrompt,
        ]
        if turns.isEmpty {
            blocks.append(noConversationLine)
        } else {
            blocks.append(heading(shown: turns.count, total: totalTurns))
            for turn in turns {
                if let user = turn.user {
                    blocks.append(userLabel + clip(user))
                }
                if options.includeAssistantReplies {
                    blocks.append(contentsOf: turn.assistant.map { assistantLabel + clip($0) })
                }
            }
        }
        if options.includeChangedFiles, !handoff.transcript.changedFiles.isEmpty {
            blocks.append(changedFilesHeading)
            blocks.append(handoff.transcript.changedFiles.map { fileBullet + $0 }.joined(separator: lineSeparator))
        }
        return blocks.joined(separator: blockSeparator)
    }

    private static func heading(shown: Int, total: Int) -> String {
        guard shown < total else { return conversationHeading }
        return conversationHeading + " (last \(shown) of \(total) turns)"
    }

    private static func clip(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxMessageCharacters else { return trimmed }
        return String(trimmed.prefix(maxMessageCharacters)) + clippedMarker
    }
}
