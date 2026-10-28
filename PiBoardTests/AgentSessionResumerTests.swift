import Foundation
import Testing
@testable import PiBoard

@MainActor
struct AgentSessionResumerTests {
    @Test func reportsWorktreeMissingWithoutLaunching() async throws {
        let runtimeRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        let manager = AgentProcessManager(agents: .pi())
        let resumer = AgentSessionResumer(processes: manager, worktrees: FakeWorktreeService(), agents: .pi())
        let project = makeProject(path: runtimeRoot)
        var task = makeTask(projectID: project.id)
        task.runContext = .worktree
        task.worktreePath = nil
        task.sessionID = UUID().uuidString

        let outcome = await resumer.resume(task: task, project: project, sharesCurrentTree: false)

        #expect(outcome == .worktreeMissing)
        #expect(manager.sessions.isEmpty)
    }

    @Test func reportsFailedWhenTheTaskHasNoSession() async throws {
        let runtimeRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        let manager = AgentProcessManager(agents: .pi())
        let resumer = AgentSessionResumer(processes: manager, worktrees: FakeWorktreeService(), agents: .pi())
        let project = makeProject(path: runtimeRoot)
        var task = makeTask(projectID: project.id)
        task.runContext = .current
        task.sessionID = nil

        let outcome = await resumer.resume(task: task, project: project, sharesCurrentTree: false)

        if case .failed = outcome {
        } else {
            Issue.record("expected .failed, got \(outcome)")
        }
        #expect(manager.sessions.isEmpty)
    }

    @Test func reportsSessionNotFoundWhenTheSessionsDirectoryLacksTheFile() async throws {
        let runtimeRoot = try makeTempDirectory()
        let agentDir = try makeTempDirectory()
        let projectPath = try makeTempDirectory()
        defer {
            for url in [runtimeRoot, agentDir, projectPath] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        try FileManager.default.createDirectory(
            at: PiSessionLocator.sessionsDirectory(agentDir: agentDir, cwd: projectPath),
            withIntermediateDirectories: true
        )
        let runtime = missingRuntime(root: runtimeRoot)
        let agents = AgentRegistry.pi(agentDirectory: agentDir, runtime: { try runtime.activeEntry() })
        let manager = AgentProcessManager(agents: agents)
        let resumer = AgentSessionResumer(processes: manager, worktrees: FakeWorktreeService(), agents: agents)
        let project = makeProject(path: projectPath)
        let sessionID = UUID()
        var task = makeTask(projectID: project.id)
        task.runContext = .current
        task.sessionID = sessionID.uuidString

        let outcome = await resumer.resume(task: task, project: project, sharesCurrentTree: false)

        #expect(outcome == .sessionNotFound(sessionID: sessionID.uuidString, cwd: projectPath))
    }

    @Test func reportsFailedWhenTheRuntimeIsMissing() async throws {
        let runtimeRoot = try makeTempDirectory()
        let agentDir = try makeTempDirectory()
        let projectPath = try makeTempDirectory()
        defer {
            for url in [runtimeRoot, agentDir, projectPath] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let runtime = missingRuntime(root: runtimeRoot)
        let agents = AgentRegistry.pi(agentDirectory: agentDir, runtime: { try runtime.activeEntry() })
        let manager = AgentProcessManager(agents: agents)
        let resumer = AgentSessionResumer(processes: manager, worktrees: FakeWorktreeService(), agents: agents)
        let project = makeProject(path: projectPath)
        var task = makeTask(projectID: project.id)
        task.runContext = .current
        task.sessionID = UUID().uuidString

        let outcome = await resumer.resume(task: task, project: project, sharesCurrentTree: false)

        #expect(outcome == .failed(AgentProcessManager.LaunchError.runtimeNotReady(.pi).localizedDescription))
        #expect(manager.sessions.isEmpty)
    }

    @Test func reportsSessionNotFoundWhenTheSessionIDIsNotAUUID() async throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let manager = AgentProcessManager(agents: .pi())
        let resumer = AgentSessionResumer(processes: manager, worktrees: FakeWorktreeService(), agents: .pi())
        let project = makeProject(path: projectPath)
        var task = makeTask(projectID: project.id)
        task.runContext = .current
        task.sessionID = "ses_not_a_uuid"

        let outcome = await resumer.resume(task: task, project: project, sharesCurrentTree: false)

        #expect(outcome == .sessionNotFound(sessionID: "ses_not_a_uuid", cwd: projectPath))
        #expect(manager.sessions.isEmpty)
    }

    @Test func reportsSessionNotFoundWhenTheAdapterSaysNo() async throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let sessionID = "gone-session"
        let adapter = FakeAgentAdapter(sessionExistsResult: false)
        let agents = AgentRegistry([adapter])
        let manager = AgentProcessManager(agents: agents)
        let resumer = AgentSessionResumer(processes: manager, worktrees: FakeWorktreeService(), agents: agents)
        let project = makeProject(path: projectPath)
        var task = makeTask(projectID: project.id)
        task.runContext = .current
        task.sessionID = sessionID

        let outcome = await resumer.resume(task: task, project: project, sharesCurrentTree: false)

        #expect(outcome == .sessionNotFound(sessionID: sessionID, cwd: projectPath))
        #expect(adapter.sessionExistsCalls == [sessionID])
        #expect(adapter.launches.isEmpty)
    }

    @Test func continuesWhenExistenceIsUnknown() async throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let adapter = FakeAgentAdapter(sessionExistsResult: nil)
        let agents = AgentRegistry([adapter])
        let manager = AgentProcessManager(agents: agents)
        let resumer = AgentSessionResumer(processes: manager, worktrees: FakeWorktreeService(), agents: agents)
        let project = makeProject(path: projectPath)
        var task = makeTask(projectID: project.id)
        task.runContext = .current
        task.sessionID = UUID().uuidString

        let outcome = await resumer.resume(task: task, project: project, sharesCurrentTree: false)

        #expect(outcome == .failed(AgentProcessManager.LaunchError.runtimeNotReady(.pi).localizedDescription))
        #expect(adapter.launches.count == 1)
    }

    private func missingRuntime(root: URL) -> PiRuntimeManager {
        let runtime = PiRuntimeManager(paths: AgentRuntimePaths(root: root))
        runtime.refresh()
        return runtime
    }

    private func makeProject(path: URL) -> Project {
        Project(id: UUID(), name: "Test", path: path, defaultAgent: .default, createdAt: Date(), updatedAt: Date())
    }

    private func makeTask(projectID: UUID) -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: projectID,
            agent: .default,
            title: "Task",
            prompt: "",
            status: .inProgress,
            position: 0,
            sessionID: nil,
            runContext: nil,
            worktreePath: nil,
            worktreeBranch: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
