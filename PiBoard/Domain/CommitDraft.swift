import Foundation

/// The working tree as git reports it: what the panel and the commit sheet both show.
/// Staging is read from git on every load, never stored here.
struct ChangeSet: Equatable, Sendable {
    let repository: URL
    let branch: String?
    let changes: [GitChange]
    let diff: GitDiff

    var stagedCount: Int { changes.count { $0.isStaged } }
    var hasStagedChanges: Bool { stagedCount > 0 }

    func staging(of path: String) -> GitChange.Staging {
        changes.first { $0.path == path }?.staging ?? .unstaged
    }
}

/// What a commit sends: the index state plus the message the user typed.
struct CommitDraft: Equatable, Sendable {
    var changeSet: ChangeSet
    var message = ""

    var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canCommit: Bool { changeSet.hasStagedChanges && !trimmedMessage.isEmpty }
}

/// Unified diff split per file. The budget only catches pathological output (a huge generated
/// file or a binary mistaken for text); per-file folding in the view keeps a large diff usable.
struct GitDiff: Equatable, Sendable {
    static let maxBytes = 10 * 1024 * 1024
    static let maxLines = 100_000
    private static let newline: UInt8 = 0x0A
    private static let newlineSeparator = "\n"
    private static let fileHeaderPrefix = "diff --git "
    private static let newPathPrefix = "+++ b/"
    private static let oldPathPrefix = "--- a/"
    private static let quote: Character = "\""

    /// The kept files joined; a file that does not fit the budget is dropped whole, because a
    /// partial file would mislead more than it helps.
    let text: String
    let isTruncated: Bool
    let files: [GitFileDiff]
    let omittedFileCount: Int

    static let empty = GitDiff(text: "", isTruncated: false, files: [], omittedFileCount: 0)

    /// `untracked` is rendered as all-added files, since `git diff` never lists them.
    static func make(unified: String, untracked: [UntrackedFile] = []) -> GitDiff {
        var text = unified
        if !text.isEmpty, !text.hasSuffix("\n") {
            text.append("\n")
        }
        for file in untracked {
            text.append(file.unifiedDiff)
        }
        var kept: [GitFileDiff] = []
        var bytes = 0
        var lines = 0
        var omitted = 0
        for file in splitFiles(text) {
            let fileBytes = file.text.utf8.count + newlineSeparator.utf8.count
            guard bytes + fileBytes <= maxBytes, lines + file.lineCount <= maxLines else {
                omitted += 1
                continue
            }
            bytes += fileBytes
            lines += file.lineCount
            kept.append(file)
        }
        let keptText = kept.map { $0.text + newlineSeparator }.joined()
        return GitDiff(text: keptText, isTruncated: omitted > 0, files: kept, omittedFileCount: omitted)
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
            let fileText = current.joined(separator: newlineSeparator)
            let newlines = fileText.utf8.count { $0 == newline }
            // Text without a trailing newline holds one more line than it has newlines.
            let lineCount = fileText.utf8.last == newline ? newlines : newlines + 1
            files.append(GitFileDiff(path: path, text: fileText, lineCount: lineCount))
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
    let lineCount: Int
    var id: String { path }
}

/// A file git does not know yet, rendered the way `git diff` would show it after `add`.
struct UntrackedFile: Equatable, Sendable {
    enum Body: Equatable, Sendable {
        case text(String)
        case binary
        /// Larger than `UntrackedFile.maxBytes`; listing it line by line would flood the view.
        case tooLarge
    }

    /// Past this a file is listed as too large instead of being read into the diff.
    static let maxBytes = 1024 * 1024
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
        guard data.count <= maxBytes else {
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
    enum Staging: Equatable, Sendable {
        /// Nothing of this change is in the index.
        case unstaged
        /// The whole change is in the index; a commit records it as shown.
        case staged
        /// Staged, then edited again: the index holds an older version of the file.
        case partiallyStaged
    }

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
        static let unchanged: Character = " "
    }

    /// Porcelain v1: column X is the index, column Y the worktree. `??` has no index entry.
    var staging: Staging {
        guard status != PorcelainCode.untracked, let index = status.first, let worktree = status.last else { return .unstaged }
        guard index != PorcelainCode.unchanged else { return .unstaged }
        return worktree == PorcelainCode.unchanged ? .staged : .partiallyStaged
    }

    var isStaged: Bool { staging != .unstaged }

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
