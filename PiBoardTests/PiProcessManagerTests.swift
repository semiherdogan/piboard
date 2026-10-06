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
                cwd: project.path,
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
                cwd: project.path,
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

    @Test func resumeThrowsWorktreeMissingForMissingWorktreePath() throws {
        let runtimeRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        let runtime = PiRuntimeManager(paths: PiRuntimePaths(root: runtimeRoot))
        runtime.refresh()

        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let project = Project(id: UUID(), name: "Test", path: projectPath, createdAt: Date(), updatedAt: Date())
        let missingWorktree = runtimeRoot.appendingPathComponent("missing-worktree")
        var task = makeTask(projectID: project.id)
        task.runContext = .worktree
        task.worktreePath = missingWorktree

        let manager = PiProcessManager()

        do {
            _ = try manager.resume(
                task: task,
                project: project,
                runContext: .worktree,
                cwd: missingWorktree,
                sessionID: UUID(),
                runtime: runtime
            )
            Issue.record("expected worktreeMissing to be thrown")
        } catch PiProcessManager.LaunchError.worktreeMissing(let url) {
            #expect(url == missingWorktree)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(manager.currentTreeOwners.isEmpty)
    }

    @Test func resumeThrowsProjectPathMissingForNonexistentPath() throws {
        let runtimeRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        let runtime = PiRuntimeManager(paths: PiRuntimePaths(root: runtimeRoot))
        runtime.refresh()

        let missingPath = runtimeRoot.appendingPathComponent("does-not-exist")
        let project = Project(id: UUID(), name: "Test", path: missingPath, createdAt: Date(), updatedAt: Date())
        let manager = PiProcessManager(piAgentDirectory: runtimeRoot)

        do {
            _ = try manager.resume(
                task: makeTask(projectID: project.id),
                project: project,
                runContext: .current,
                cwd: missingPath,
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

    // The session check runs before the runtime check, so a missing runtime does not mask it.
    @Test func resumeThrowsSessionNotFoundWhenSessionsDirectoryLacksFile() throws {
        let runtimeRoot = try makeTempDirectory()
        let agentDir = try makeTempDirectory()
        let projectPath = try makeTempDirectory()
        defer {
            for url in [runtimeRoot, agentDir, projectPath] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let runtime = PiRuntimeManager(paths: PiRuntimePaths(root: runtimeRoot))
        runtime.refresh()
        try FileManager.default.createDirectory(
            at: PiSessionLocator.sessionsDirectory(agentDir: agentDir, cwd: projectPath),
            withIntermediateDirectories: true
        )
        let project = Project(id: UUID(), name: "Test", path: projectPath, createdAt: Date(), updatedAt: Date())
        let sessionID = UUID()
        let manager = PiProcessManager(piAgentDirectory: agentDir)

        do {
            _ = try manager.resume(
                task: makeTask(projectID: project.id),
                project: project,
                runContext: .current,
                cwd: projectPath,
                sessionID: sessionID,
                runtime: runtime
            )
            Issue.record("expected sessionNotFound to be thrown")
        } catch PiProcessManager.LaunchError.sessionNotFound(let missing) {
            #expect(missing == sessionID)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    // Pi may store sessions elsewhere, so a missing default directory skips the check.
    @Test func resumeSkipsSessionCheckWhenSessionsDirectoryIsMissing() throws {
        let runtimeRoot = try makeTempDirectory()
        let agentDir = try makeTempDirectory()
        let projectPath = try makeTempDirectory()
        defer {
            for url in [runtimeRoot, agentDir, projectPath] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let runtime = PiRuntimeManager(paths: PiRuntimePaths(root: runtimeRoot))
        runtime.refresh()
        let project = Project(id: UUID(), name: "Test", path: projectPath, createdAt: Date(), updatedAt: Date())
        let manager = PiProcessManager(piAgentDirectory: agentDir)

        do {
            _ = try manager.resume(
                task: makeTask(projectID: project.id),
                project: project,
                runContext: .current,
                cwd: projectPath,
                sessionID: UUID(),
                runtime: runtime
            )
            Issue.record("expected runtimeNotReady to be thrown")
        } catch PiProcessManager.LaunchError.runtimeNotReady {
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func worktreeLaunchesDoNotTakeCurrentTreeLock() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let manager = PiProcessManager()
        let first = UUID()
        let second = UUID()

        let firstLock = try manager.acquireCurrentTreeLockIfNeeded(runContext: .worktree, cwd: projectPath, taskID: first)
        let secondLock = try manager.acquireCurrentTreeLockIfNeeded(runContext: .worktree, cwd: projectPath, taskID: second)
        manager.runtimeStates[first] = .running
        manager.runtimeStates[second] = .running

        #expect(firstLock == nil)
        #expect(secondLock == nil)
        #expect(manager.currentTreeOwners.isEmpty)
        #expect(manager.hasActiveCurrentTreeSession(projectPath: projectPath) == false)
    }

    @Test func secondCurrentTreeLaunchOnSameProjectIsBusy() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let manager = PiProcessManager()
        let owner = UUID()

        let locked = try manager.acquireCurrentTreeLockIfNeeded(runContext: .current, cwd: projectPath, taskID: owner)

        #expect(locked == PiProcessManager.canonicalPath(projectPath))
        #expect(throws: PiProcessManager.LaunchError.self) {
            try manager.acquireCurrentTreeLockIfNeeded(runContext: .current, cwd: projectPath, taskID: UUID())
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

    @Test func activeSessionCountCountsStartingRunningAndStopping() {
        let manager = PiProcessManager()
        #expect(manager.activeSessionCount == 0)

        manager.runtimeStates[UUID()] = .starting
        manager.runtimeStates[UUID()] = .running
        manager.runtimeStates[UUID()] = .stopping
        manager.runtimeStates[UUID()] = .notStarted
        manager.runtimeStates[UUID()] = .exited(0)
        manager.runtimeStates[UUID()] = .failed("boom")

        #expect(manager.activeSessionCount == 3)
    }

    @Test func versionsInUseIncludesOnlyActiveSessions() {
        let manager = PiProcessManager()
        let running = UUID()
        let exited = UUID()
        manager.runtimeStates[running] = .running
        manager.runtimeStates[exited] = .exited(0)
        manager.runtimeVersions[running] = "1.0.0"
        manager.runtimeVersions[exited] = "0.9.0"

        #expect(manager.versionsInUse == ["1.0.0"])
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
