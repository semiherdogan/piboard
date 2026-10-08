import Foundation
import Synchronization
import Testing
@testable import PiBoard

final class FakeGitWriter: GitWriting {
    struct Calls {
        var staged: [URL] = []
        var committed: [(message: String, path: URL)] = []
        var upstreamReads: Int = 0
        var discarded: [GitChange] = []
    }

    let commitError: (any Error)?
    let upstreamResult: Result<String?, any Error>
    let discardError: (any Error)?
    private let calls = Mutex(Calls())

    init(commitError: (any Error)? = nil, upstreamResult: Result<String?, any Error> = .success(nil), discardError: (any Error)? = nil) {
        self.commitError = commitError
        self.upstreamResult = upstreamResult
        self.discardError = discardError
    }

    var staged: [URL] { calls.withLock { $0.staged } }
    var committed: [(message: String, path: URL)] { calls.withLock { $0.committed } }
    var upstreamReads: Int { calls.withLock { $0.upstreamReads } }
    var discarded: [GitChange] { calls.withLock { $0.discarded } }

    func stageAll(at path: URL) async throws {
        calls.withLock { $0.staged.append(path) }
    }

    func commit(message: String, at path: URL) async throws {
        if let commitError {
            throw commitError
        }
        calls.withLock { $0.committed.append((message, path)) }
    }

    func upstream(at path: URL) async throws -> String? {
        calls.withLock { $0.upstreamReads += 1 }
        return try upstreamResult.get()
    }

    func discard(_ change: GitChange, at path: URL) async throws {
        if let discardError {
            throw discardError
        }
        calls.withLock { $0.discarded.append(change) }
    }
}

@MainActor
final class FakeGitTerminalRunner: GitTerminalRunning {
    var outcomes: [GitTerminalOutcome]
    private(set) var starts: [(arguments: [String], directory: URL)] = []

    init(outcomes: [GitTerminalOutcome]) {
        self.outcomes = outcomes
    }

    func start(_ arguments: [String], in directory: URL) -> GitTerminalRun {
        starts.append((arguments, directory))
        let outcome = outcomes.count > 1 ? outcomes.removeFirst() : (outcomes.first ?? .exited(0))
        return GitTerminalRun(session: PTYSession(), outcome: Task { outcome })
    }
}

final class FakeCommitMessageGenerator: CommitMessageGenerating, Sendable {
    let result: Result<String, any Error>
    private let storage = Mutex<CommitPromptContext?>(nil)

    init(result: Result<String, any Error>) {
        self.result = result
    }

    var lastContext: CommitPromptContext? { storage.withLock { $0 } }

    func generate(_ context: CommitPromptContext) async throws -> String {
        storage.withLock { $0 = context }
        return try result.get()
    }
}

@MainActor
struct CommitActionsTests {
    private static let path = URL(fileURLWithPath: "/tmp/project")
    private static let diffText = "diff --git a/README.md b/README.md\n--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-a\n+b\n"

    private func makeActions(
        info: RepositoryInfo = RepositoryInfo(isRepository: true, topLevel: path, headBranch: "main"),
        changes: [GitChange] = [GitChange(status: " M", path: "README.md")],
        diff: String = diffText,
        recentSubjectsResult: Result<[String], any Error> = .success([]),
        writer: FakeGitWriter = FakeGitWriter(),
        terminal: FakeGitTerminalRunner = FakeGitTerminalRunner(outcomes: [.exited(0)]),
        generator: FakeCommitMessageGenerator = FakeCommitMessageGenerator(result: .success("feat: thing"))
    ) -> CommitActions {
        let git = FakeGitService(
            repositoryInfoResult: .success(info),
            statusResult: .success(changes),
            diffResult: .success(diff),
            recentSubjectsResult: recentSubjectsResult
        )
        return CommitActions(git: git, writer: writer, terminal: terminal, generator: generator)
    }

    @Test func beginLoadsTheDraft() async throws {
        let actions = makeActions()
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        #expect(actions.phase == .editing)
        #expect(actions.draft?.changes.count == 1)
        #expect(actions.draft?.branch == "main")
        #expect(actions.draft?.diff.files.map(\.path) == ["README.md"])
        #expect(actions.lastError == nil)
    }

    @Test func beginOnANonRepositoryReportsIt() async throws {
        let actions = makeActions(info: .notARepository)
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        #expect(actions.draft == nil)
        #expect(actions.lastError == CommitActions.notARepositoryMessage)
        #expect(actions.phase == .editing)
        #expect(actions.request != nil)
    }

    @Test func generateMessageFillsTheDraft() async throws {
        let actions = makeActions(generator: FakeCommitMessageGenerator(result: .success("feat: thing")))
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.generateMessage()
        await actions.actionTask?.value

        #expect(actions.message == "feat: thing")
        #expect(actions.phase == .editing)

        let failing = makeActions(generator: FakeCommitMessageGenerator(result: .failure(GitServiceError.timedOut)))
        failing.begin(path: Self.path, title: "Task")
        await failing.actionTask?.value

        failing.generateMessage()
        await failing.actionTask?.value

        #expect(failing.message == "")
        #expect(failing.lastError != nil)
        #expect(failing.phase == .editing)
    }

    @Test func commitStagesAndCommitsThenCloses() async throws {
        let writer = FakeGitWriter()
        let terminal = FakeGitTerminalRunner(outcomes: [.exited(0)])
        let actions = makeActions(writer: writer, terminal: terminal)
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.setMessage("fix: readme")
        actions.commit(andPush: false)
        await actions.actionTask?.value

        #expect(writer.staged == [Self.path])
        #expect(writer.committed.first?.message == "fix: readme")
        #expect(actions.revision == 1)
        #expect(actions.request == nil)
        #expect(terminal.starts.isEmpty)
    }

    @Test func commitWithABlankMessageDoesNothing() async throws {
        let writer = FakeGitWriter()
        let actions = makeActions(writer: writer)
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.commit(andPush: false)
        await actions.actionTask?.value

        #expect(writer.staged.isEmpty)
        #expect(writer.committed.isEmpty)
        #expect(actions.request != nil)
    }

    @Test func aFailedCommitKeepsTheSheetOpen() async throws {
        let writer = FakeGitWriter(commitError: GitServiceError.commandFailed(code: 1, stderr: "hook rejected"))
        let actions = makeActions(writer: writer)
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.setMessage("fix: readme")
        actions.commit(andPush: false)
        await actions.actionTask?.value

        #expect(actions.lastError?.contains("hook rejected") == true)
        #expect(actions.isCommitted == false)
        #expect(actions.request != nil)
        #expect(actions.phase == .editing)
    }

    @Test func commitAndPushSetsTheUpstreamOnFirstPush() async throws {
        let writer = FakeGitWriter(upstreamResult: .success(nil))
        let terminal = FakeGitTerminalRunner(outcomes: [.exited(0)])
        let actions = makeActions(writer: writer, terminal: terminal)
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.setMessage("fix: readme")
        actions.commit(andPush: true)
        await actions.actionTask?.value

        #expect(terminal.starts.first?.arguments == ["push", "--set-upstream", "origin", "main"])
        #expect(terminal.starts.first?.directory == Self.path)
        #expect(actions.request == nil)
        #expect(actions.revision == 1)
    }

    @Test func commitAndPushWithAnUpstreamPushesPlainly() async throws {
        let writer = FakeGitWriter(upstreamResult: .success("origin/main"))
        let terminal = FakeGitTerminalRunner(outcomes: [.exited(0)])
        let actions = makeActions(writer: writer, terminal: terminal)
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.setMessage("fix: readme")
        actions.commit(andPush: true)
        await actions.actionTask?.value

        #expect(terminal.starts.first?.arguments == ["push"])
    }

    @Test func aFailedPushKeepsTheConsoleAndAllowsRetry() async throws {
        let writer = FakeGitWriter()
        let terminal = FakeGitTerminalRunner(outcomes: [.exited(1), .exited(0)])
        let actions = makeActions(writer: writer, terminal: terminal)
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.setMessage("fix: readme")
        actions.commit(andPush: true)
        await actions.actionTask?.value

        #expect(actions.request != nil)
        #expect(actions.isCommitted == true)
        #expect(actions.pushRun != nil)
        #expect(actions.lastError?.contains("1") == true)
        #expect(actions.phase == .editing)
        #expect(writer.committed.count == 1)

        actions.retryPush()
        await actions.actionTask?.value

        #expect(terminal.starts.count == 2)
        #expect(actions.request == nil)
        #expect(writer.committed.count == 1)
    }

    @Test func aTimedOutPushReportsIt() async throws {
        let writer = FakeGitWriter()
        let terminal = FakeGitTerminalRunner(outcomes: [.timedOut])
        let actions = makeActions(writer: writer, terminal: terminal)
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.setMessage("fix: readme")
        actions.commit(andPush: true)
        await actions.actionTask?.value

        #expect(actions.lastError?.contains("timed out") == true)
        #expect(actions.request != nil)
    }

    @Test func pushOnADetachedHeadCommitsButDoesNotPush() async throws {
        let info = RepositoryInfo(isRepository: true, topLevel: Self.path, headBranch: nil)
        let writer = FakeGitWriter()
        let terminal = FakeGitTerminalRunner(outcomes: [.exited(0)])
        let actions = makeActions(info: info, writer: writer, terminal: terminal)
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.setMessage("fix: readme")
        actions.commit(andPush: true)
        await actions.actionTask?.value

        #expect(writer.committed.count == 1)
        #expect(terminal.starts.isEmpty)
        #expect(actions.lastError == CommitActions.detachedHeadMessage)
        #expect(actions.request != nil)
    }

    @Test func generateMessageSendsRecentSubjectsAndBudgetedDiff() async throws {
        let generator = FakeCommitMessageGenerator(result: .success("feat: thing"))
        let actions = makeActions(recentSubjectsResult: .success(["one", "two", "three", "four"]), generator: generator)
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.generateMessage()
        await actions.actionTask?.value

        #expect(generator.lastContext?.recentSubjects == ["one", "two", "three"])
        #expect(generator.lastContext?.diff.hasPrefix(PromptDiffBudget.filesHeader) == true)
        #expect(generator.lastContext?.branch == "main")
    }

    @Test func toggleReviewedIsTrackedOnTheDraft() async throws {
        let actions = makeActions()
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.toggleReviewed("README.md")
        #expect(actions.draft?.reviewedCount == 1)

        actions.toggleReviewed("README.md")
        #expect(actions.draft?.reviewedCount == 0)
    }

    @Test func requestDiscardOpensTheConfirmation() async throws {
        let actions = makeActions()
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.requestDiscard(GitChange(status: " M", path: "README.md"))
        #expect(actions.discardRequest?.change.path == "README.md")

        actions.cancelDiscard()
        #expect(actions.discardRequest == nil)
    }

    @Test func requestDiscardIgnoresARename() async throws {
        let actions = makeActions()
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.requestDiscard(GitChange(status: "R ", path: "README.md"))
        #expect(actions.discardRequest == nil)
    }

    @Test func confirmDiscardCallsTheWriterAndReloadsKeepingMessageAndReviewed() async throws {
        let writer = FakeGitWriter()
        let actions = makeActions(writer: writer)
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.setMessage("wip")
        actions.toggleReviewed("README.md")
        actions.requestDiscard(GitChange(status: " M", path: "README.md"))
        actions.confirmDiscard()
        await actions.actionTask?.value

        #expect(writer.discarded.count == 1)
        #expect(actions.revision == 1)
        #expect(actions.message == "wip")
        #expect(actions.draft?.reviewedCount == 1)
        #expect(actions.phase == .editing)
        #expect(actions.request != nil)
    }

    @Test func aFailedDiscardKeepsTheSheetOpenWithAnError() async throws {
        let writer = FakeGitWriter(discardError: GitServiceError.commandFailed(code: 1, stderr: "locked"))
        let actions = makeActions(writer: writer)
        actions.begin(path: Self.path, title: "Task")
        await actions.actionTask?.value

        actions.requestDiscard(GitChange(status: " M", path: "README.md"))
        actions.confirmDiscard()
        await actions.actionTask?.value

        #expect(actions.lastError?.contains("locked") == true)
        #expect(actions.phase == .editing)
        #expect(actions.draft != nil)
    }
}
