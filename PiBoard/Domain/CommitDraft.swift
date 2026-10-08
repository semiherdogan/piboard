import Foundation

/// What the commit sheet shows and sends, independent of how it was loaded.
struct CommitDraft: Equatable, Sendable {
    let repository: URL
    let branch: String?
    let changes: [GitChange]
    let diff: GitDiff
    var message = ""
    /// A reading aid only: staging always takes every change, reviewed or not.
    var reviewedPaths: Set<String> = []

    var reviewedCount: Int {
        changes.count { reviewedPaths.contains($0.path) }
    }

    var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canCommit: Bool {
        !changes.isEmpty && !trimmedMessage.isEmpty
    }

    func isReviewed(_ path: String) -> Bool {
        reviewedPaths.contains(path)
    }

    mutating func toggleReviewed(_ path: String) {
        if reviewedPaths.remove(path) == nil {
            reviewedPaths.insert(path)
        }
    }
}

/// Unified diff split per file, clipped to a budget a sheet can render and a prompt can carry.
struct GitDiff: Equatable, Sendable {
    static let maxBytes = 200 * 1024
    static let maxLines = 2000
    private static let fileHeaderPrefix = "diff --git "
    private static let newPathPrefix = "+++ b/"
    private static let oldPathPrefix = "--- a/"
    private static let quote: Character = "\""

    /// Clipped at the budget; `files` is empty once clipping happened because a partial last
    /// file would mislead more than it helps.
    let text: String
    let isTruncated: Bool
    let files: [GitFileDiff]

    static let empty = GitDiff(text: "", isTruncated: false, files: [])

    /// `untracked` is rendered as all-added files, since `git diff` never lists them.
    static func make(unified: String, untracked: [UntrackedFile] = []) -> GitDiff {
        var text = unified
        if !text.isEmpty, !text.hasSuffix("\n") {
            text.append("\n")
        }
        for file in untracked {
            text.append(file.unifiedDiff)
        }
        guard !exceedsBudget(text) else {
            return GitDiff(text: clip(text), isTruncated: true, files: [])
        }
        return GitDiff(text: text, isTruncated: false, files: splitFiles(text))
    }

    static func exceedsBudget(_ text: String) -> Bool {
        text.utf8.count > maxBytes || text.filter { $0 == "\n" }.count > maxLines
    }

    static func clip(_ text: String) -> String {
        var lines = 0
        var bytes = 0
        var end = text.startIndex
        for index in text.indices {
            let character = text[index]
            bytes += character.utf8.count
            if character == "\n" {
                lines += 1
            }
            if bytes > maxBytes || lines > maxLines {
                break
            }
            end = text.index(after: index)
        }
        return String(text[..<end])
    }

    /// Each `diff --git` header opens a file; the path comes from the `+++` line, or `---` for
    /// a deletion whose new side is /dev/null.
    static func splitFiles(_ text: String) -> [GitFileDiff] {
        var files: [GitFileDiff] = []
        var current: [Substring] = []
        func flush() {
            guard !current.isEmpty, let path = path(in: current) else {
                current = []
                return
            }
            files.append(GitFileDiff(path: path, text: current.joined(separator: "\n")))
            current = []
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(fileHeaderPrefix) {
                flush()
            }
            current.append(line)
        }
        flush()
        return files
    }

    private static func path(in lines: [Substring]) -> String? {
        var fallback: String?
        for rawLine in lines {
            let line = stripQuotes(rawLine)
            if line.hasPrefix(newPathPrefix) {
                return String(line.dropFirst(newPathPrefix.count))
            }
            if fallback == nil, line.hasPrefix(oldPathPrefix) {
                fallback = String(line.dropFirst(oldPathPrefix.count))
            }
        }
        return fallback
    }

    /// Git quotes the whole path including the a/ or b/ marker, e.g. `+++ "b/f\303\266o.txt"`;
    /// strip the pair so the prefix check above still matches.
    private static func stripQuotes(_ line: Substring) -> Substring {
        guard let firstQuote = line.firstIndex(of: quote), line.last == quote, firstQuote != line.index(before: line.endIndex) else {
            return line
        }
        var result = line
        result.remove(at: result.index(before: result.endIndex))
        result.remove(at: firstQuote)
        return result
    }
}

struct GitFileDiff: Equatable, Sendable, Identifiable {
    let path: String
    /// Header and hunks for this file, as git printed them.
    let text: String
    var id: String { path }
}

/// A file git does not know yet, rendered the way `git diff` would show it after `add`.
struct UntrackedFile: Equatable, Sendable {
    enum Body: Equatable, Sendable {
        case text(String)
        case binary
        /// Larger than the whole diff budget; listing it line by line would only get clipped.
        case tooLarge
    }

    static let binaryPlaceholder = "Binary file"
    static let tooLargePlaceholder = "File too large to show"
    private static let devNull = "/dev/null"
    private static let newFileModeLine = "new file mode 100644"

    let path: String
    let body: Body

    static func read(path: String, in root: URL) -> UntrackedFile {
        let url = root.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else {
            return UntrackedFile(path: path, body: .binary)
        }
        guard data.count <= GitDiff.maxBytes else {
            return UntrackedFile(path: path, body: .tooLarge)
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            return UntrackedFile(path: path, body: .binary)
        }
        return UntrackedFile(path: path, body: .text(contents))
    }

    var unifiedDiff: String {
        var lines = ["diff --git a/\(path) b/\(path)", Self.newFileModeLine, "--- \(Self.devNull)", "+++ b/\(path)"]
        switch body {
        case .text(let contents):
            let body = contents.split(separator: "\n", omittingEmptySubsequences: false)
            let withoutTrailingEmpty = contents.hasSuffix("\n") ? body.dropLast() : body[...]
            lines.append("@@ -0,0 +1,\(withoutTrailingEmpty.count) @@")
            lines.append(contentsOf: withoutTrailingEmpty.map { "+" + $0 })
        case .binary:
            lines.append(Self.binaryPlaceholder)
        case .tooLarge:
            lines.append(Self.tooLargePlaceholder)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension GitChange {
    enum Kind: Equatable, Sendable {
        case untracked
        case added
        case modified
        case deleted
        case renamed
        case copied
        case conflicted
        case other

        var label: String {
            switch self {
            case .untracked: "New"
            case .added: "Added"
            case .modified: "Modified"
            case .deleted: "Deleted"
            case .renamed: "Renamed"
            case .copied: "Copied"
            case .conflicted: "Conflict"
            case .other: "Changed"
            }
        }

        /// A rename or copy carries a second path the status list does not keep, and a conflict
        /// needs a merge decision, so neither can be discarded blindly.
        var canDiscard: Bool {
            switch self {
            case .untracked, .added, .modified, .deleted, .other: true
            case .renamed, .copied, .conflicted: false
            }
        }
    }

    private enum PorcelainCode {
        static let untracked = "??"
        static let added: Character = "A"
        static let modified: Character = "M"
        static let typeChanged: Character = "T"
        static let deleted: Character = "D"
        static let renamed: Character = "R"
        static let copied: Character = "C"
        static let unmerged: Character = "U"
    }

    /// The index column wins over the worktree column, matching what `git status` prints first.
    var kind: Kind {
        guard status != PorcelainCode.untracked else { return .untracked }
        let codes = Array(status)
        if codes.contains(PorcelainCode.unmerged) { return .conflicted }
        for code in codes {
            switch code {
            case PorcelainCode.added: return .added
            case PorcelainCode.modified, PorcelainCode.typeChanged: return .modified
            case PorcelainCode.deleted: return .deleted
            case PorcelainCode.renamed: return .renamed
            case PorcelainCode.copied: return .copied
            default: continue
            }
        }
        return .other
    }
}
