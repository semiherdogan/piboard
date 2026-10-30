import Foundation

/// The prompt and output cleanup shared by every agent that drafts commit messages.
enum CommitMessagePrompt {
    static let systemPrompt = """
    You write Git commit messages. Reply with the message only: no code fences, no quotes, no preamble.
    First line: imperative mood, at most 72 characters, no trailing period. \
    Add a blank line and a short body only when the diff needs explaining.
    """
    static let promptHeader = "Write a commit message for this diff."
    static let branchPrefix = "Branch: "
    static let examplesHeader = "Recent commit message examples from this repository. Match their style only when it fits the diff:"
    static let exampleBullet = "- "
    static let diffHeader = "Diff:"
    private static let codeFence = "```"
    private static let leadingMarkers: CharacterSet = ["-", "*", ">", "`", "\"", "'", " "]
    private static let trailingMarkers: CharacterSet = ["`", "\"", "'"]

    static func prompt(for context: CommitPromptContext) -> String {
        var sections: [String] = []
        if !context.recentSubjects.isEmpty {
            sections.append(([examplesHeader] + context.recentSubjects.map { exampleBullet + $0 }).joined(separator: "\n"))
        }
        var header = [promptHeader]
        if let branch = context.branch {
            header.append(branchPrefix + branch)
        }
        sections.append(header.joined(separator: "\n"))
        sections.append(diffHeader + "\n" + context.diff)
        return sections.joined(separator: "\n\n")
    }

    /// Strips the code fence a model sometimes adds despite the instructions, then the leading
    /// list marker or quote and trailing quote a model sometimes wraps the first line in.
    static func sanitize(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(codeFence), text.hasSuffix(codeFence) {
            text.removeLast(codeFence.count)
            if let firstLineEnd = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstLineEnd)...])
            } else {
                text.removeFirst(codeFence.count)
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let firstLineEnd = text.firstIndex(of: "\n") else {
            return stripMarkers(text)
        }
        let firstLine = stripMarkers(String(text[..<firstLineEnd]))
        let rest = text[firstLineEnd...]
        return (firstLine + rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripMarkers(_ line: String) -> String {
        var line = line
        while let first = line.unicodeScalars.first, leadingMarkers.contains(first) {
            line.removeFirst()
        }
        while let last = line.unicodeScalars.last, trailingMarkers.contains(last) {
            line.removeLast()
        }
        return line
    }
}
