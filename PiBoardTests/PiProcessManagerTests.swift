import Foundation
import Testing
@testable import PiBoard

@MainActor
struct PiProcessManagerTests {
    @Test func canonicalPathResolvesSymlinkedTmp() {
        let direct = PiProcessManager.canonicalPath(URL(fileURLWithPath: "/tmp"))
        let viaPrivate = PiProcessManager.canonicalPath(URL(fileURLWithPath: "/private/tmp"))

        #expect(direct == viaPrivate)
    }

    @Test func startThrowsRuntimeNotReadyWhenRuntimeIsNotReady() throws {
        let runtimeRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        let runtime = PiRuntimeManager(paths: PiRuntimePaths(root: runtimeRoot))
        runtime.refresh()
        #expect(runtime.status == .missing)

        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let project = Project(id: UUID(), name: "Test", path: projectPath, createdAt: Date(), updatedAt: Date())
        let task = makeTask(projectID: project.id)

        let manager = PiProcessManager()

        #expect(throws: PiProcessManager.LaunchError.self) {
            try manager.start(
                task: task,
                project: project,
                runContext: .current,
                prompt: "",
                sessionID: UUID(),
                runtime: runtime
            )
        }
    }

    @Test func startThrowsProjectPathMissingForNonexistentPath() throws {
        let runtimeRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        let runtime = PiRuntimeManager(paths: PiRuntimePaths(root: runtimeRoot))
        runtime.refresh()

        let missingPath = runtimeRoot.appendingPathComponent("does-not-exist")
        let project = Project(id: UUID(), name: "Test", path: missingPath, createdAt: Date(), updatedAt: Date())
        let task = makeTask(projectID: project.id)

        let manager = PiProcessManager()

        do {
            _ = try manager.start(
                task: task,
                project: project,
                runContext: .current,
                prompt: "",
                sessionID: UUID(),
                runtime: runtime
            )
            Issue.record("expected projectPathMissing to be thrown")
        } catch PiProcessManager.LaunchError.projectPathMissing(let url) {
            #expect(url == missingPath)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func hasActiveCurrentTreeSessionIsFalseByDefault() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let manager = PiProcessManager()

        #expect(manager.hasActiveCurrentTreeSession(projectPath: projectPath) == false)
    }

    @Test func hasActiveCurrentTreeSessionIsTrueWhileRunning() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let manager = PiProcessManager()
        let taskID = UUID()
        let canonicalPath = PiProcessManager.canonicalPath(projectPath)
        _ = manager.lock.acquire(path: canonicalPath, taskID: taskID)
        manager.runtimeStates[taskID] = .running

        #expect(manager.hasActiveCurrentTreeSession(projectPath: projectPath) == true)
    }

    @Test func hasActiveCurrentTreeSessionIsFalseAfterExit() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let manager = PiProcessManager()
        let taskID = UUID()
        let canonicalPath = PiProcessManager.canonicalPath(projectPath)
        _ = manager.lock.acquire(path: canonicalPath, taskID: taskID)
        manager.runtimeStates[taskID] = .exited(0)

        #expect(manager.hasActiveCurrentTreeSession(projectPath: projectPath) == false)
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
