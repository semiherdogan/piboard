import Foundation
import Testing
@testable import PiBoard

struct CommitDraftTests {
    private static let path = URL(fileURLWithPath: "/tmp/project")

    private func makeChangeSet(_ changes: [GitChange]) -> ChangeSet {
        ChangeSet(repository: Self.path, branch: nil, changes: changes, diff: .empty)
    }

    // MARK: GitDiff.splitFiles

    @Test func splitFilesReadsPathsFromPlusPlusPlusLine() {
        let text = """
        diff --git a/foo.swift b/foo.swift
        index 111..222 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1 +1 @@
        -old
        +new
        diff --git a/bar.swift b/bar.swift
        index 333..444 100644
        --- a/bar.swift
        +++ b/bar.swift
        @@ -1 +1 @@
        -old2
        +new2
        """
        let files = GitDiff.splitFiles(text)

        #expect(files.map(\.path) == ["foo.swift", "bar.swift"])
    }

    @Test func splitFilesFallsBackToOldPathForADeletion() {
        let text = """
        diff --git a/gone.swift b/gone.swift
        deleted file mode 100644
        --- a/gone.swift
        +++ /dev/null
        @@ -1 +0,0 @@
        -old
        """
        let files = GitDiff.splitFiles(text)

        #expect(files.map(\.path) == ["gone.swift"])
    }

    @Test func splitFilesUnquotesAQuotedPath() {
        let text = """
        diff --git a/with space.txt b/with space.txt
        index 111..222 100644
        --- "a/with space.txt"
        +++ "b/with space.txt"
        @@ -1 +1 @@
        -old
        +new
        """
        let files = GitDiff.splitFiles(text)

        #expect(files.map(\.path) == ["with space.txt"])
    }

    // MARK: GitDiff.make

    @Test func makeAppendsUntrackedFileAsAnAddedDiff() {
        let untracked = UntrackedFile(path: "new.txt", body: .text("a\nb\n"))
        let diff = GitDiff.make(unified: "", untracked: [untracked])

        #expect(diff.files.map(\.path) == ["new.txt"])
        #expect(diff.files[0].text.contains("@@ -0,0 +1,2 @@"))
        #expect(diff.files[0].text.contains("+a"))
        #expect(diff.files[0].text.contains("+b"))
    }

    private static func fileDiff(path: String, body: [String]) -> String {
        let header = ["diff --git a/\(path) b/\(path)", "--- a/\(path)", "+++ b/\(path)"]
        return (header + body).joined(separator: "\n") + "\n"
    }

    @Test func makeDropsTheFileThatPushesTheDiffOverTheLineBudget() {
        let hugeBody = (0...GitDiff.maxLines).map { _ in "+x" }
        let unified = Self.fileDiff(path: "first.txt", body: ["+a"])
            + Self.fileDiff(path: "second.txt", body: ["+b"])
            + Self.fileDiff(path: "third.txt", body: hugeBody)
        let diff = GitDiff.make(unified: unified)

        #expect(diff.files.count == 2)
        #expect(diff.omittedFileCount == 1)
        #expect(diff.isTruncated)
        #expect(diff.text.contains("first.txt"))
        #expect(diff.text.contains("second.txt"))
        #expect(!diff.text.contains("third.txt"))
    }

    @Test func makeDropsASingleFileOverTheByteBudget() {
        let unified = Self.fileDiff(path: "big.txt", body: [String(repeating: "x", count: GitDiff.maxBytes + 1)])
        let diff = GitDiff.make(unified: unified)

        #expect(diff.files.isEmpty)
        #expect(diff.omittedFileCount == 1)
        #expect(diff.isTruncated)
    }

    @Test func makeKeepsEverythingWithinTheBudget() {
        let diff = GitDiff.make(unified: Self.fileDiff(path: "a.txt", body: ["+a"]))

        #expect(diff.omittedFileCount == 0)
        #expect(!diff.isTruncated)
    }

    @Test func lineCountCountsTheLinesSplitFilesKeepsForTheFile() {
        let files = GitDiff.splitFiles("diff --git a/f b/f\n--- a/f\n+++ b/f\n")

        #expect(files.map(\.lineCount) == [3])
    }

    // MARK: UntrackedFile.read

    @Test func readOfInvalidUtf8BytesIsBinary() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0xFF, 0xFE, 0x00]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = UntrackedFile.read(path: url.lastPathComponent, in: url.deletingLastPathComponent())

        #expect(file.body == .binary)
    }

    @Test func readOfAFileLargerThanTheUntrackedLimitIsTooLarge() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 0x61, count: UntrackedFile.maxBytes + 1).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = UntrackedFile.read(path: url.lastPathComponent, in: url.deletingLastPathComponent())

        #expect(file.body == .tooLarge)
    }

    @Test func readOfAFileExactlyAtTheUntrackedLimitIsText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 0x61, count: UntrackedFile.maxBytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = UntrackedFile.read(path: url.lastPathComponent, in: url.deletingLastPathComponent())

        #expect(file.body == .text(String(repeating: "a", count: UntrackedFile.maxBytes)))
    }

    @Test func readOfAUtf8FileIsText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("hello\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = UntrackedFile.read(path: url.lastPathComponent, in: url.deletingLastPathComponent())

        #expect(file.body == .text("hello\n"))
    }

    // MARK: ChangeSet

    @Test func stagedCountCountsFullyAndPartiallyStagedChanges() {
        let changes = [
            GitChange(status: "M ", path: "a.swift"),
            GitChange(status: "MM", path: "b.swift"),
            GitChange(status: " M", path: "c.swift"),
        ]
        let changeSet = makeChangeSet(changes)

        #expect(changeSet.stagedCount == 2)
        #expect(changeSet.hasStagedChanges)
        #expect(changeSet.staging(of: "b.swift") == .partiallyStaged)
        #expect(changeSet.staging(of: "missing.swift") == .unstaged)
    }

    // MARK: CommitDraft

    @Test func canCommitIsFalseWhenNothingIsStaged() {
        let draft = CommitDraft(changeSet: makeChangeSet([GitChange(status: " M", path: "a.swift")]), message: "feat: thing")

        #expect(!draft.canCommit)
    }

    @Test func canCommitRequiresStagedChangesAndAMessage() {
        let changes = [GitChange(status: "M ", path: "a.swift")]

        let blankMessage = CommitDraft(changeSet: makeChangeSet(changes), message: "   ")
        #expect(!blankMessage.canCommit)

        let noChanges = CommitDraft(changeSet: makeChangeSet([]), message: "feat: thing")
        #expect(!noChanges.canCommit)

        let ready = CommitDraft(changeSet: makeChangeSet(changes), message: "feat: thing")
        #expect(ready.canCommit)
        #expect(ready.trimmedMessage == "feat: thing")
    }

    // MARK: GitChange.staging

    @Test func stagingReadsTheIndexAndWorktreeColumns() {
        #expect(GitChange(status: "??", path: "a").staging == .unstaged)
        #expect(GitChange(status: " M", path: "a").staging == .unstaged)
        #expect(GitChange(status: "M ", path: "a").staging == .staged)
        #expect(GitChange(status: "A ", path: "a").staging == .staged)
        #expect(GitChange(status: "MM", path: "a").staging == .partiallyStaged)
        #expect(GitChange(status: "AM", path: "a").staging == .partiallyStaged)
        #expect(GitChange(status: "D ", path: "a").staging == .staged)
        #expect(GitChange(status: " D", path: "a").staging == .unstaged)
    }

    // MARK: GitChange.kind

    @Test func kindMapsPorcelainCodes() {
        #expect(GitChange(status: "??", path: "a").kind == .untracked)
        #expect(GitChange(status: " M", path: "a").kind == .modified)
        #expect(GitChange(status: "A ", path: "a").kind == .added)
        #expect(GitChange(status: "D ", path: "a").kind == .deleted)
        #expect(GitChange(status: "R ", path: "a").kind == .renamed)
        #expect(GitChange(status: "UU", path: "a").kind == .conflicted)
        #expect(GitChange(status: "MM", path: "a").kind == .modified)
    }

    @Test func canDiscardAllowsOnlyPlainChanges() {
        #expect(GitChange.Kind.modified.canDiscard)
        #expect(GitChange.Kind.untracked.canDiscard)
        #expect(GitChange.Kind.added.canDiscard)
        #expect(GitChange.Kind.deleted.canDiscard)
        #expect(!GitChange.Kind.renamed.canDiscard)
        #expect(!GitChange.Kind.copied.canDiscard)
        #expect(!GitChange.Kind.conflicted.canDiscard)
    }
}
