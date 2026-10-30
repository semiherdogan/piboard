import Foundation

/// A conversation read back from an agent's own store, text only: tool calls and tool output are
/// reduced to the files they changed. Built by the readers, consumed by `SessionHandoffRenderer`.
struct SessionTranscript: Equatable, Sendable {
    enum Role: Equatable, Sendable { case user, assistant }

    struct Message: Equatable, Sendable {
        let role: Role
        let text: String
        let timestamp: Date?
    }

    var messages: [Message] = []
    /// Paths the agent wrote to, in first-seen order, deduplicated; relative or absolute as the agent recorded them.
    var changedFiles: [String] = []

    mutating func noteChangedFile(_ path: String) {
        guard !path.isEmpty, !changedFiles.contains(path) else { return }
        changedFiles.append(path)
    }

    /// Appends a message unless its text is empty or whitespace only.
    mutating func append(_ role: Role, text: String, timestamp: Date?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messages.append(Message(role: role, text: text, timestamp: timestamp))
    }
}
