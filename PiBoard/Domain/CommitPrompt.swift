import Foundation

/// Everything the message generator gets to see. Built by `CommitActions`, consumed by any
/// `CommitMessageGenerating`, so swapping the model never touches the sheet.
struct CommitPromptContext: Equatable, Sendable {
    let diff: String
    let branch: String?
    /// Newest first, subjects only, for style; empty in a repository without commits.
    let recentSubjects: [String]
}

/// Clips a diff for a prompt. Separate from `GitDiff`'s on-screen budget: a model reads a lot
/// less than a scrolling view shows, and a few long files should not crowd out the file list.
enum PromptDiffBudget {
    static let maxFiles = 20
    static let maxLinesPerFile = 150
    static let maxBytes = 48 * 1024
    static let maxSubjects = 3
    static let maxSubjectLength = 160
    static let filesHeader = "Files:"
    static let fileIndent = "  "
    static let moreLinesFormat = "... (%d more lines)"
    static let moreFilesFormat = "... and %d more files not shown"
    private static let subjectEllipsis = "..."

    /// The file list always comes first and in full, so even a clipped diff names every change.
    static func render(diff: GitDiff, changes: [GitChange]) -> String {
        var lines = [filesHeader]
        lines.append(contentsOf: changes.map { fileIndent + $0.kind.label + " " + $0.path })
        lines.append("")
        var text = lines.joined(separator: "\n") + "\n"
        guard !diff.isTruncated, !diff.files.isEmpty else {
            // No per-file split is available; take the raw head within the byte budget.
            return text + clipBytes(diff.text, to: maxBytes - text.utf8.count)
        }
        var shown = 0
        for file in diff.files.prefix(maxFiles) {
            let body = clipLines(file.text)
            guard text.utf8.count + body.utf8.count <= maxBytes else { break }
            text += body
            if !body.hasSuffix("\n") { text += "\n" }
            shown += 1
        }
        let omitted = diff.files.count - shown
        if omitted > 0 {
            text += String(format: moreFilesFormat, omitted) + "\n"
        }
        return text
    }

    static func clipLines(_ fileDiff: String) -> String {
        let lines = fileDiff.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLinesPerFile else { return fileDiff }
        let kept = lines.prefix(maxLinesPerFile).joined(separator: "\n")
        return kept + "\n" + String(format: moreLinesFormat, lines.count - maxLinesPerFile) + "\n"
    }

    /// Cuts on a character boundary so a multibyte path is never split in half.
    static func clipBytes(_ text: String, to budget: Int) -> String {
        guard budget > 0 else { return "" }
        guard text.utf8.count > budget else { return text }
        var bytes = 0
        var end = text.startIndex
        for index in text.indices {
            bytes += text[index].utf8.count
            if bytes > budget { break }
            end = text.index(after: index)
        }
        return String(text[..<end])
    }

    static func subjects(_ raw: [String]) -> [String] {
        raw.lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maxSubjects)
            .map { subject in
                guard subject.count > maxSubjectLength else { return subject }
                return String(subject.prefix(maxSubjectLength - subjectEllipsis.count)).trimmingCharacters(in: .whitespaces) + subjectEllipsis
            }
    }
}
