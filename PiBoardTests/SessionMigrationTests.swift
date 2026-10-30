import Foundation
import Testing
@testable import PiBoard

struct SessionMigrationTests {
    private let projectPath = URL(fileURLWithPath: "/tmp/migration-project")
    private let worktreePath = URL(fileURLWithPath: "/tmp/migration-worktree")

    @Test func cannotMigrateWithoutASession() {
        #expect(!SessionMigration.canMigrate(makeTask(sessionID: nil), isRunning: false))
    }

    @Test func cannotMigrateWhileRunning() {
        #expect(!SessionMigration.canMigrate(makeTask(sessionID: "s"), isRunning: true))
    }

    @Test func canMigrateAnIdleTaskWithASession() {
        #expect(SessionMigration.canMigrate(makeTask(sessionID: "s"), isRunning: false))
    }

    @Test func targetsExcludeTheCurrentAgentAndKeepTheEnabledOrder() {
        let task = makeTask(sessionID: "s", agent: .opencode)
        let targets = SessionMigration.targets(for: task, enabled: [.claudeCode, .opencode, .pi])
        #expect(targets == [.claudeCode, .pi])
    }

    @Test func targetsAreEmptyWhenOnlyTheCurrentAgentIsEnabled() {
        let task = makeTask(sessionID: "s", agent: .pi)
        #expect(SessionMigration.targets(for: task, enabled: [.pi]).isEmpty)
    }

    @Test func launchDirectoryPicksTheWorktreeForAWorktreeTask() {
        let task = makeTask(sessionID: "s", runContext: .worktree, worktreePath: worktreePath)
        let directory = SessionMigration.launchDirectory(task: task, project: makeProject())
        #expect(directory.context == .worktree)
        #expect(directory.cwd == worktreePath)
    }

    @Test func launchDirectoryFallsBackToTheProjectWithoutAWorktreePath() {
        let task = makeTask(sessionID: "s", runContext: .worktree, worktreePath: nil)
        let directory = SessionMigration.launchDirectory(task: task, project: makeProject())
        #expect(directory.context == .current)
        #expect(directory.cwd == projectPath)
    }

    @Test func launchDirectoryIgnoresAWorktreePathInTheCurrentTree() {
        let task = makeTask(sessionID: "s", runContext: .current, worktreePath: worktreePath)
        let directory = SessionMigration.launchDirectory(task: task, project: makeProject())
        #expect(directory.context == .current)
        #expect(directory.cwd == projectPath)
    }

    private func makeProject() -> Project {
        Project(id: UUID(), name: "P", path: projectPath, defaultAgent: .default, createdAt: Date(), updatedAt: Date())
    }

    private func makeTask(
        sessionID: String?,
        agent: AgentKind = .default,
        runContext: RunContext? = nil,
        worktreePath: URL? = nil
    ) -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: UUID(),
            agent: agent,
            title: "Task",
            prompt: "",
            status: .inProgress,
            position: 0,
            sessionID: sessionID,
            runContext: runContext,
            worktreePath: worktreePath,
            worktreeBranch: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
