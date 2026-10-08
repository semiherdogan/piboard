import Foundation
import Testing
@testable import PiBoard

struct CommitDraftTests {
    private static let path = URL(fileURLWithPath: "/tmp/project")

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

    @Test func makeTruncatesWhenOverTheLineBudget() {
        let unified = Array(repeating: "line", count: 2001).joined(separator: "\n")
        let diff = GitDiff.make(unified: unified)

        #expect(diff.isTruncated)
        #expect(diff.files.isEmpty)
        #expect(diff.text.filter { $0 == "\n" }.count <= GitDiff.maxLines)
    }

    @Test func makeTruncatesWhenOverTheByteBudget() {
        let unified = String(repeating: "a", count: GitDiff.maxBytes + 1)
        let diff = GitDiff.make(unified: unified)

        #expect(diff.isTruncated)
        #expect(diff.text.utf8.count <= GitDiff.maxBytes)
    }

    // MARK: UntrackedFile.read

    @Test func readOfInvalidUtf8BytesIsBinary() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0xFF, 0xFE, 0x00]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = UntrackedFile.read(path: url.lastPathComponent, in: url.deletingLastPathComponent())

        #expect(file.body == .binary)
    }

    @Test func readOfAFileLargerThanTheBudgetIsTooLarge() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 0x61, count: GitDiff.maxBytes + 1).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = UntrackedFile.read(path: url.lastPathComponent, in: url.deletingLastPathComponent())

        #expect(file.body == .tooLarge)
    }

    @Test func readOfAUtf8FileIsText() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("hello\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = UntrackedFile.read(path: url.lastPathComponent, in: url.deletingLastPathComponent())

        #expect(file.body == .text("hello\n"))
    }

    // MARK: CommitDraft

    @Test func toggleReviewedAddsThenRemoves() {
        var draft = CommitDraft(repository: Self.path, branch: nil, changes: [], diff: .empty)

        draft.toggleReviewed("a.swift")
        #expect(draft.isReviewed("a.swift"))

        draft.toggleReviewed("a.swift")
        #expect(!draft.isReviewed("a.swift"))
    }

    @Test func reviewedCountCountsOnlyPathsPresentInChanges() {
        let changes = [GitChange(status: " M", path: "a.swift"), GitChange(status: " M", path: "b.swift")]
        var draft = CommitDraft(repository: Self.path, branch: nil, changes: changes, diff: .empty)

        draft.reviewedPaths = ["a.swift", "stale.swift"]

        #expect(draft.reviewedCount == 1)
    }

    @Test func canCommitRequiresChangesAndAMessage() {
        let changes = [GitChange(status: " M", path: "a.swift")]

        var blankMessage = CommitDraft(repository: Self.path, branch: nil, changes: changes, diff: .empty)
        blankMessage.message = "   "
        #expect(!blankMessage.canCommit)

        var noChanges = CommitDraft(repository: Self.path, branch: nil, changes: [], diff: .empty)
        noChanges.message = "feat: thing"
        #expect(!noChanges.canCommit)

        var ready = CommitDraft(repository: Self.path, branch: nil, changes: changes, diff: .empty)
        ready.message = "feat: thing"
        #expect(ready.canCommit)
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
