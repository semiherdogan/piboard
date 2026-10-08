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
        let shells: ShellSessions
        let actions: DeletionActions
        let projectPath: URL
        let agentDir: URL
        let projectID: UUID
        let taskIDs: [UUID]
    }

    /// Worktrees are only planned for removal when they still exist, so the fixture creates real
    /// directories and removes them again afterwards.
    private func makeFixture(taskCount: Int, worktreeCount: Int = 0, removeError: (any Error)? = nil) throws -> Fixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let projectPath = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
        let agentDir = root.appendingPathComponent("agent")

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
        let shells = ShellSessions(makeSession: { PTYSession() }, start: { _, _ in })
        return Fixture(
            board: board,
            processes: processes,
            worktrees: worktrees,
            attention: attention,
            shells: shells,
            actions: DeletionActions(board: board, processes: processes, worktrees: worktrees, attention: attention, shells: shells, piAgentDirectory: agentDir),
            projectPath: projectPath,
            agentDir: agentDir,
            projectID: projectID,
            taskIDs: taskIDs
        )
    }

    private func project(_ fixture: Fixture) throws -> Project {
        try #require(fixture.board.projects.first { $0.id == fixture.projectID })
    }

    /// Gives the task a session id and writes the empty file Pi would have left for it.
    @discardableResult
    private func attachSession(to taskID: UUID, in fixture: Fixture) throws -> URL {
        let sessionID = UUID()
        fixture.board.setPiSessionID(sessionID, for: taskID)
        let directory = PiSessionLocator.sessionsDirectory(agentDir: fixture.agentDir, cwd: fixture.projectPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("2026-10-06T13-02-02-447Z_\(sessionID.uuidString.lowercased()).jsonl")
        try Data().write(to: file)
        return file
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

    @Test func theDoneTasksPlanCoversOnlyDoneTasks() throws {
        let fixture = try makeFixture(taskCount: 3)
        fixture.board.move(taskID: fixture.taskIDs[0], to: .done, at: 0)
        fixture.board.move(taskID: fixture.taskIDs[2], to: .done, at: 0)

        let plan = fixture.actions.plan(forDoneTasksIn: try project(fixture))
        #expect(Set(plan.taskIDs) == [fixture.taskIDs[0], fixture.taskIDs[2]])
        #expect(plan.taskIDs.count == 2)
    }

    @Test func theTaskPlanListsItsSessionFileAndSkipsTasksWithoutOne() throws {
        let fixture = try makeFixture(taskCount: 2)
        let file = try attachSession(to: fixture.taskIDs[0], in: fixture)
        let withSession = try #require(fixture.board.tasks.first { $0.id == fixture.taskIDs[0] })
        let without = try #require(fixture.board.tasks.first { $0.id == fixture.taskIDs[1] })

        let plan = fixture.actions.plan(forTask: withSession)
        #expect(plan.sessions == [PlannedSessionRemoval(taskID: fixture.taskIDs[0], file: file)])
        #expect(fixture.actions.plan(forTask: without).sessions.isEmpty)
    }

    // MARK: Performing

    @Test func deletingATaskRemovesItsSessionFileOnly() async throws {
        let fixture = try makeFixture(taskCount: 2)
        let deleted = try attachSession(to: fixture.taskIDs[0], in: fixture)
        let kept = try attachSession(to: fixture.taskIDs[1], in: fixture)
        let task = try #require(fixture.board.tasks.first { $0.id == fixture.taskIDs[0] })

        await fixture.actions.perform(fixture.actions.plan(forTask: task))

        #expect(!FileManager.default.fileExists(atPath: deleted.path))
        #expect(FileManager.default.fileExists(atPath: kept.path))
    }

    @Test func deletingAProjectRemovesAllItsSessionFiles() async throws {
        let fixture = try makeFixture(taskCount: 2)
        let files = try fixture.taskIDs.map { try attachSession(to: $0, in: fixture) }
        let plan = fixture.actions.plan(forProject: try project(fixture))
        #expect(plan.sessions.count == 2)

        await fixture.actions.perform(plan)

        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func clearingDoneRemovesOnlyDoneTasks() async throws {
        let fixture = try makeFixture(taskCount: 3)
        fixture.board.move(taskID: fixture.taskIDs[0], to: .done, at: 0)
        fixture.board.move(taskID: fixture.taskIDs[2], to: .done, at: 0)
        let plan = fixture.actions.plan(forDoneTasksIn: try project(fixture))

        await fixture.actions.perform(plan)

        #expect(fixture.board.tasks.map(\.id) == [fixture.taskIDs[1]])
        #expect(fixture.board.projects.count == 1)
    }

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

    @Test func deletingAProjectClosesItsShell() async throws {
        let fixture = try makeFixture(taskCount: 1)
        fixture.shells.open(projectID: fixture.projectID, directory: fixture.projectPath)
        #expect(fixture.shells.session(for: fixture.projectID) != nil)
        let plan = fixture.actions.plan(forProject: try project(fixture))

        await fixture.actions.perform(plan)

        #expect(fixture.shells.session(for: fixture.projectID) == nil)
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
