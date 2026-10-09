import Foundation
import Testing
@testable import PiBoard

@MainActor
struct PiSessionResumerTests {
    @Test func reportsWorktreeMissingWithoutLaunching() async throws {
        let runtimeRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        let manager = PiProcessManager()
        let resumer = PiSessionResumer(processes: manager, worktrees: FakeWorktreeService(), runtime: missingRuntime(root: runtimeRoot))
        let project = makeProject(path: runtimeRoot)
        var task = makeTask(projectID: project.id)
        task.runContext = .worktree
        task.worktreePath = nil
        task.piSessionId = UUID()

        let outcome = await resumer.resume(task: task, project: project, sharesCurrentTree: false)

        #expect(outcome == .worktreeMissing)
        #expect(manager.sessions.isEmpty)
    }

    @Test func reportsFailedWhenTheTaskHasNoSession() async throws {
        let runtimeRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        let manager = PiProcessManager()
        let resumer = PiSessionResumer(processes: manager, worktrees: FakeWorktreeService(), runtime: missingRuntime(root: runtimeRoot))
        let project = makeProject(path: runtimeRoot)
        var task = makeTask(projectID: project.id)
        task.runContext = .current
        task.piSessionId = nil

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
        let manager = PiProcessManager(piAgentDirectory: agentDir)
        let resumer = PiSessionResumer(processes: manager, worktrees: FakeWorktreeService(), runtime: missingRuntime(root: runtimeRoot))
        let project = makeProject(path: projectPath)
        let sessionID = UUID()
        var task = makeTask(projectID: project.id)
        task.runContext = .current
        task.piSessionId = sessionID

        let outcome = await resumer.resume(task: task, project: project, sharesCurrentTree: false)

        #expect(outcome == .sessionNotFound(sessionID: sessionID, cwd: projectPath))
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
        let manager = PiProcessManager(piAgentDirectory: agentDir)
        let resumer = PiSessionResumer(processes: manager, worktrees: FakeWorktreeService(), runtime: missingRuntime(root: runtimeRoot))
        let project = makeProject(path: projectPath)
        var task = makeTask(projectID: project.id)
        task.runContext = .current
        task.piSessionId = UUID()

        let outcome = await resumer.resume(task: task, project: project, sharesCurrentTree: false)

        #expect(outcome == .failed(PiProcessManager.LaunchError.runtimeNotReady.localizedDescription))
        #expect(manager.sessions.isEmpty)
    }

    private func missingRuntime(root: URL) -> PiRuntimeManager {
        let runtime = PiRuntimeManager(paths: PiRuntimePaths(root: root))
        runtime.refresh()
        return runtime
    }

    private func makeProject(path: URL) -> Project {
        Project(id: UUID(), name: "Test", path: path, createdAt: Date(), updatedAt: Date())
    }

    private func makeTask(projectID: UUID) -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: projectID,
            title: "Task",
            prompt: "",
            status: .inProgress,
            position: 0,
            piSessionId: nil,
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
