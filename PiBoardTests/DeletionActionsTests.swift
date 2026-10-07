import Foundation
import Testing
@testable import PiBoard

@MainActor
struct DeletionActionsTests {
    private struct Fixture {
        let board: BoardModel
        let processes: PiProcessManager
        let worktrees: FakeWorktreeService
        let attention: TaskAttention
        let actions: DeletionActions
        let projectPath: URL
        let projectID: UUID
        let taskIDs: [UUID]
    }

    /// Worktrees are only planned for removal when they still exist, so the fixture creates real
    /// directories and removes them again afterwards.
    private func makeFixture(taskCount: Int, worktreeCount: Int = 0, removeError: (any Error)? = nil) throws -> Fixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let projectPath = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)

        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let board = BoardModel(database: database)
        board.addProject(name: "Project", path: projectPath)
        let projectID = try #require(board.projects.first?.id)

        var taskIDs: [UUID] = []
        for index in 0..<taskCount {
            board.addTask(title: "Task \(index)", prompt: "", to: projectID)
            let taskID = try #require(board.tasks.last?.id)
            taskIDs.append(taskID)
            guard index < worktreeCount else { continue }
            let worktreePath = root.appendingPathComponent("worktree-\(index)")
            try FileManager.default.createDirectory(at: worktreePath, withIntermediateDirectories: true)
            board.setRunContext(.worktree, for: taskID)
            board.setWorktree(path: worktreePath, branch: "piboard/task-\(index)", for: taskID)
        }

        let processes = PiProcessManager()
        let worktrees = FakeWorktreeService(removeError: removeError)
        let attention = TaskAttention()
        return Fixture(
            board: board,
            processes: processes,
            worktrees: worktrees,
            attention: attention,
            actions: DeletionActions(board: board, processes: processes, worktrees: worktrees, attention: attention),
            projectPath: projectPath,
            projectID: projectID,
            taskIDs: taskIDs
        )
    }

    private func project(_ fixture: Fixture) throws -> Project {
        try #require(fixture.board.projects.first { $0.id == fixture.projectID })
    }

    // MARK: Planning

    @Test func theProjectPlanCoversEveryTaskAndWorktree() throws {
        let fixture = try makeFixture(taskCount: 3, worktreeCount: 2)
        let plan = fixture.actions.plan(forProject: try project(fixture))

        #expect(plan.taskIDs.count == 3)
        #expect(plan.worktrees.count == 2)
        #expect(plan.runningTaskIDs.isEmpty)
    }

    @Test func runningAgentsAreListedInThePlan() throws {
        let fixture = try makeFixture(taskCount: 3)
        fixture.processes.runtimeStates[fixture.taskIDs[0]] = .running
        fixture.processes.runtimeStates[fixture.taskIDs[1]] = .starting
        fixture.processes.runtimeStates[fixture.taskIDs[2]] = .exited(0)

        let plan = fixture.actions.plan(forProject: try project(fixture))
        #expect(Set(plan.runningTaskIDs) == Set(fixture.taskIDs.prefix(2)))
    }

    // A task left pointing at a folder somebody deleted by hand has nothing to remove.
    @Test func aWorktreeThatIsAlreadyGoneIsNotPlanned() throws {
        let fixture = try makeFixture(taskCount: 1, worktreeCount: 1)
        let path = try #require(fixture.board.tasks.first?.worktreePath)
        try FileManager.default.removeItem(at: path)

        let plan = fixture.actions.plan(forProject: try project(fixture))
        #expect(plan.worktrees.isEmpty)
    }

    @Test func aTaskRunningInTheProjectTreeHasNoWorktreeToRemove() throws {
        let fixture = try makeFixture(taskCount: 1)
        let plan = fixture.actions.plan(forProject: try project(fixture))
        #expect(plan.worktrees.isEmpty)
    }

    @Test func theTaskPlanCoversOnlyThatTask() throws {
        let fixture = try makeFixture(taskCount: 3, worktreeCount: 3)
        let task = try #require(fixture.board.tasks.first { $0.id == fixture.taskIDs[1] })

        let plan = fixture.actions.plan(forTask: task)
        #expect(plan.taskIDs == [fixture.taskIDs[1]])
        #expect(plan.worktrees.map(\.taskID) == [fixture.taskIDs[1]])
    }

    // MARK: Performing

    @Test func deletingAProjectRemovesItsWorktreesAndPrunesTheRepository() async throws {
        let fixture = try makeFixture(taskCount: 2, worktreeCount: 2)
        // The project stores a canonicalised path, and it is gone once the delete has run.
        let canonicalPath = try project(fixture).path
        let plan = fixture.actions.plan(forProject: try project(fixture))

        await fixture.actions.perform(plan)

        #expect(fixture.worktrees.recorded.removed.count == 2)
        // Forced: the confirmation already warned that uncommitted changes would be lost.
        let allForced = fixture.worktrees.recorded.removed.allSatisfy { $0.force }
        #expect(allForced)
        #expect(fixture.worktrees.recorded.pruned == [canonicalPath])
        #expect(fixture.board.projects.isEmpty)
        #expect(fixture.board.tasks.isEmpty)
    }

    @Test func theRepositoryIsPrunedOnceForSeveralWorktrees() async throws {
        let fixture = try makeFixture(taskCount: 3, worktreeCount: 3)
        let plan = fixture.actions.plan(forProject: try project(fixture))
        await fixture.actions.perform(plan)
        #expect(fixture.worktrees.recorded.pruned.count == 1)
    }

    /// A deleted task must not keep a runtime version pinned as "in use" or leave its working tree
    /// locked by an owner that no longer exists.
    @Test func deletingClearsTheProcessBookkeeping() async throws {
        let fixture = try makeFixture(taskCount: 1)
        let taskID = fixture.taskIDs[0]
        fixture.processes.runtimeStates[taskID] = .exited(0)
        fixture.processes.runtimeVersions[taskID] = "1.0.4"
        _ = try fixture.processes.acquireCurrentTreeLockIfNeeded(runContext: .current, cwd: fixture.projectPath, taskID: taskID)
        let plan = fixture.actions.plan(forProject: try project(fixture))

        await fixture.actions.perform(plan)

        #expect(fixture.processes.runtimeVersions[taskID] == nil)
        #expect(fixture.processes.runtimeStates[taskID] == nil)
        #expect(fixture.processes.currentTreeOwners.isEmpty)
        #expect(!fixture.processes.hasActiveCurrentTreeSession(projectPath: fixture.projectPath))
    }

    @Test func deletingClearsAnyPendingDot() async throws {
        let fixture = try makeFixture(taskCount: 2)
        for taskID in fixture.taskIDs {
            fixture.attention.mark(taskID: taskID)
        }
        let plan = fixture.actions.plan(forProject: try project(fixture))

        await fixture.actions.perform(plan)
        #expect(fixture.attention.taskIDs.isEmpty)
    }

    @Test func deletingOneTaskLeavesTheRestAlone() async throws {
        let fixture = try makeFixture(taskCount: 3, worktreeCount: 3)
        let task = try #require(fixture.board.tasks.first { $0.id == fixture.taskIDs[1] })
        fixture.attention.mark(taskID: fixture.taskIDs[0])

        await fixture.actions.perform(fixture.actions.plan(forTask: task))

        #expect(fixture.worktrees.recorded.removed.count == 1)
        #expect(fixture.board.tasks.count == 2)
        #expect(fixture.board.projects.count == 1)
        #expect(fixture.attention.has(taskID: fixture.taskIDs[0]))
    }

    // The rows still go away; the leftover folder is reported rather than silently ignored.
    @Test func aWorktreeThatCannotBeRemovedIsReported() async throws {
        let fixture = try makeFixture(
            taskCount: 1,
            worktreeCount: 1,
            removeError: GitServiceError.commandFailed(code: 1, stderr: "worktree is locked")
        )
        let plan = fixture.actions.plan(forProject: try project(fixture))

        await fixture.actions.perform(plan)

        #expect(fixture.board.projects.isEmpty)
        #expect(fixture.board.lastError?.contains("could not be removed") == true)
    }
}
