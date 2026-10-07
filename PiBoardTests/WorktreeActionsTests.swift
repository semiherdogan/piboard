import Foundation
import Synchronization
import Testing
@testable import PiBoard

final class FakeWorktreeService: WorktreeServicing {
    struct Calls {
        var removed: [(info: WorktreeInfo, force: Bool)] = []
        var pruned: [URL] = []
    }

    let validation: WorktreeValidation
    /// Makes `remove` fail, for the callers that have to carry on past a stuck worktree.
    let removeError: (any Error)?
    private let calls = Mutex(Calls())

    init(validation: WorktreeValidation = .valid, removeError: (any Error)? = nil) {
        self.validation = validation
        self.removeError = removeError
    }

    var recorded: Calls { calls.withLock { $0 } }

    func create(for task: BoardTask, project: Project) async throws -> WorktreeInfo {
        WorktreeInfo(path: project.path, branch: "")
    }

    func validate(_ info: WorktreeInfo) async -> WorktreeValidation {
        validation
    }

    func remove(_ info: WorktreeInfo, force: Bool) async throws {
        calls.withLock { $0.removed.append((info, force)) }
        if let removeError {
            throw removeError
        }
    }

    func prune(repository: URL) async throws {
        calls.withLock { $0.pruned.append(repository) }
    }
}

@MainActor
struct WorktreeActionsTests {
    private static let projectPath = URL(fileURLWithPath: "/tmp/project")
    private static let worktreePath = URL(fileURLWithPath: "/tmp/worktree")
    private static let branch = "piboard/abcdef12-task"

    private struct Fixture {
        let board: BoardModel
        let processes: PiProcessManager
        let worktrees: FakeWorktreeService
        let actions: WorktreeActions
        let taskID: UUID
    }

    private func makeFixture(
        validation: WorktreeValidation = .valid,
        changes: [GitChange] = [],
        sessionID: UUID? = nil
    ) throws -> Fixture {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let board = BoardModel(database: database)
        board.addProject(name: "Project", path: Self.projectPath)
        let projectID = try #require(board.projects.first?.id)
        board.addTask(title: "Task", prompt: "", to: projectID)
        let taskID = try #require(board.tasks.first?.id)
        board.setRunContext(.worktree, for: taskID)
        board.setWorktree(path: Self.worktreePath, branch: Self.branch, for: taskID)
        board.setPiSessionID(sessionID, for: taskID)

        let processes = PiProcessManager()
        let worktrees = FakeWorktreeService(validation: validation)
        let git = FakeGitService(statusResult: .success(changes))
        let actions = WorktreeActions(board: board, processes: processes, git: git, worktrees: worktrees)
        return Fixture(board: board, processes: processes, worktrees: worktrees, actions: actions, taskID: taskID)
    }

    private func task(_ fixture: Fixture) throws -> BoardTask {
        try #require(fixture.board.tasks.first { $0.id == fixture.taskID })
    }

    @Test func blockedWhileSessionIsActive() async throws {
        let fixture = try makeFixture()
        fixture.processes.runtimeStates[fixture.taskID] = .running

        await fixture.actions.removeWorktree(for: fixture.taskID)

        #expect(fixture.actions.removalRequest == nil)
        #expect(fixture.board.lastError == WorktreeActions.activeSessionMessage)
        #expect(try task(fixture).worktreePath == Self.worktreePath)
    }

    @Test func cleanWorktreeRemovesWithoutForceAndClearsFields() async throws {
        let fixture = try makeFixture()

        await fixture.actions.removeWorktree(for: fixture.taskID)
        let request = try #require(fixture.actions.removalRequest)
        #expect(request.kind == .clean)

        fixture.actions.confirmRemoval()
        #expect(fixture.actions.removalRequest == nil)
        await fixture.actions.actionTask?.value

        let removed = fixture.worktrees.recorded.removed
        #expect(removed.count == 1)
        #expect(removed.first?.info == WorktreeInfo(path: Self.worktreePath, branch: Self.branch))
        #expect(removed.first?.force == false)
        let updated = try task(fixture)
        #expect(updated.worktreePath == nil)
        #expect(updated.worktreeBranch == nil)
        #expect(updated.runContext == nil)
        #expect(fixture.actions.revision == 1)
    }

    @Test func removalKeepsRunContextWhenTaskHasSession() async throws {
        let fixture = try makeFixture(sessionID: UUID())

        await fixture.actions.removeWorktree(for: fixture.taskID)
        fixture.actions.confirmRemoval()
        await fixture.actions.actionTask?.value

        let updated = try task(fixture)
        #expect(updated.worktreePath == nil)
        #expect(updated.runContext == .worktree)
    }

    @Test func dirtyWorktreeRequiresForce() async throws {
        let changes = (0..<12).map { GitChange(status: " M", path: "file\($0).swift") }
        let fixture = try makeFixture(changes: changes)

        await fixture.actions.removeWorktree(for: fixture.taskID)
        let request = try #require(fixture.actions.removalRequest)
        #expect(request.kind == .dirty(changes: changes))
        #expect(request.confirmTitle == WorktreeActions.removeAnywayTitle)
        #expect(request.message.contains("file9.swift"))
        #expect(!request.message.contains("file10.swift"))
        #expect(request.message.contains(Self.branch))

        fixture.actions.confirmRemoval()
        await fixture.actions.actionTask?.value

        #expect(fixture.worktrees.recorded.removed.first?.force == true)
        #expect(try task(fixture).worktreePath == nil)
    }

    @Test func missingWorktreeForgetsFieldsAndPrunes() async throws {
        let fixture = try makeFixture(validation: .pathMissing)

        await fixture.actions.removeWorktree(for: fixture.taskID)
        let request = try #require(fixture.actions.removalRequest)
        #expect(request.kind == .missing)
        #expect(request.confirmTitle == WorktreeActions.forgetTitle)

        fixture.actions.confirmRemoval()
        await fixture.actions.actionTask?.value

        #expect(fixture.worktrees.recorded.removed.isEmpty)
        #expect(fixture.worktrees.recorded.pruned == fixture.board.projects.map(\.path))
        let updated = try task(fixture)
        #expect(updated.worktreePath == nil)
        #expect(updated.worktreeBranch == nil)
    }

    @Test func cancelLeavesWorktreeUntouched() async throws {
        let fixture = try makeFixture()

        await fixture.actions.removeWorktree(for: fixture.taskID)
        fixture.actions.cancelRemoval()

        #expect(fixture.actions.removalRequest == nil)
        #expect(fixture.worktrees.recorded.removed.isEmpty)
        #expect(try task(fixture).worktreePath == Self.worktreePath)
    }
}
