import Foundation
import Testing
@testable import PiBoard

@MainActor
struct AgentProcessManagerTests {
    @Test func canonicalPathResolvesSymlinkedTmp() {
        let direct = AgentProcessManager.canonicalPath(URL(fileURLWithPath: "/tmp"))
        let viaPrivate = AgentProcessManager.canonicalPath(URL(fileURLWithPath: "/private/tmp"))

        #expect(direct == viaPrivate)
    }

    @Test func startThrowsRuntimeNotReadyWhenRuntimeIsNotReady() throws {
        let runtimeRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }
        let runtime = PiRuntimeManager(paths: AgentRuntimePaths(root: runtimeRoot))
        runtime.refresh()
        #expect(runtime.status == .missing)

        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let project = Project(id: UUID(), name: "Test", path: projectPath, defaultAgent: .default, createdAt: Date(), updatedAt: Date())
        let task = makeTask(projectID: project.id)

        let manager = AgentProcessManager(agents: .pi(runtime: { try runtime.activeEntry() }))

        #expect(throws: AgentProcessManager.LaunchError.self) {
            try manager.start(
                task: task,
                project: project,
                runContext: .current,
                cwd: project.path,
                prompt: "",
                sessionID: UUID().uuidString
            )
        }
    }

    @Test func startThrowsProjectPathMissingForNonexistentPath() throws {
        let runtimeRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }

        let missingPath = runtimeRoot.appendingPathComponent("does-not-exist")
        let project = Project(id: UUID(), name: "Test", path: missingPath, defaultAgent: .default, createdAt: Date(), updatedAt: Date())
        let task = makeTask(projectID: project.id)

        let manager = AgentProcessManager(agents: .pi())

        do {
            _ = try manager.start(
                task: task,
                project: project,
                runContext: .current,
                cwd: project.path,
                prompt: "",
                sessionID: UUID().uuidString
            )
            Issue.record("expected projectPathMissing to be thrown")
        } catch AgentProcessManager.LaunchError.projectPathMissing(let url) {
            #expect(url == missingPath)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func resumeThrowsWorktreeMissingForMissingWorktreePath() throws {
        let runtimeRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }

        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let project = Project(id: UUID(), name: "Test", path: projectPath, defaultAgent: .default, createdAt: Date(), updatedAt: Date())
        let missingWorktree = runtimeRoot.appendingPathComponent("missing-worktree")
        var task = makeTask(projectID: project.id)
        task.runContext = .worktree
        task.worktreePath = missingWorktree

        let manager = AgentProcessManager(agents: .pi())

        do {
            _ = try manager.resume(
                task: task,
                project: project,
                runContext: .worktree,
                cwd: missingWorktree,
                sessionID: UUID().uuidString
            )
            Issue.record("expected worktreeMissing to be thrown")
        } catch AgentProcessManager.LaunchError.worktreeMissing(let url) {
            #expect(url == missingWorktree)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(manager.currentTreeOwners.isEmpty)
    }

    @Test func resumeThrowsProjectPathMissingForNonexistentPath() throws {
        let runtimeRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: runtimeRoot) }

        let missingPath = runtimeRoot.appendingPathComponent("does-not-exist")
        let project = Project(id: UUID(), name: "Test", path: missingPath, defaultAgent: .default, createdAt: Date(), updatedAt: Date())
        let manager = AgentProcessManager(agents: .pi(agentDirectory: runtimeRoot))

        do {
            _ = try manager.resume(
                task: makeTask(projectID: project.id),
                project: project,
                runContext: .current,
                cwd: missingPath,
                sessionID: UUID().uuidString
            )
            Issue.record("expected projectPathMissing to be thrown")
        } catch AgentProcessManager.LaunchError.projectPathMissing(let url) {
            #expect(url == missingPath)
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
        let runtime = PiRuntimeManager(paths: AgentRuntimePaths(root: runtimeRoot))
        runtime.refresh()
        let project = Project(id: UUID(), name: "Test", path: projectPath, defaultAgent: .default, createdAt: Date(), updatedAt: Date())
        let manager = AgentProcessManager(agents: .pi(agentDirectory: agentDir, runtime: { try runtime.activeEntry() }))

        do {
            _ = try manager.resume(
                task: makeTask(projectID: project.id),
                project: project,
                runContext: .current,
                cwd: projectPath,
                sessionID: UUID().uuidString
            )
            Issue.record("expected runtimeNotReady to be thrown")
        } catch AgentProcessManager.LaunchError.runtimeNotReady {
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func launchErrorFromTheAdapterMapsToRuntimeNotReady() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let project = Project(id: UUID(), name: "Test", path: projectPath, defaultAgent: .default, createdAt: Date(), updatedAt: Date())
        let adapter = FakeAgentAdapter(launchResult: .failure(AgentAdapterError.runtimeNotReady))
        let manager = AgentProcessManager(agents: AgentRegistry([adapter]))

        do {
            _ = try manager.start(
                task: makeTask(projectID: project.id),
                project: project,
                runContext: .current,
                cwd: projectPath,
                prompt: "",
                sessionID: adapter.makeSessionID()
            )
            Issue.record("expected runtimeNotReady to be thrown")
        } catch AgentProcessManager.LaunchError.runtimeNotReady {
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(adapter.launches.count == 1)
        #expect(manager.currentTreeOwners.isEmpty)
        #expect(manager.sessions.isEmpty)
    }

    @Test func invalidSessionIDFromTheAdapterMapsToLaunchError() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let project = Project(id: UUID(), name: "Test", path: projectPath, defaultAgent: .default, createdAt: Date(), updatedAt: Date())
        let adapter = FakeAgentAdapter(launchResult: .failure(AgentAdapterError.invalidSessionID("x")))
        let manager = AgentProcessManager(agents: AgentRegistry([adapter]))

        do {
            _ = try manager.start(
                task: makeTask(projectID: project.id),
                project: project,
                runContext: .current,
                cwd: projectPath,
                prompt: "",
                sessionID: "x"
            )
            Issue.record("expected invalidSessionID to be thrown")
        } catch AgentProcessManager.LaunchError.invalidSessionID(let id) {
            #expect(id == "x")
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(manager.sessions.isEmpty)
        #expect(manager.currentTreeOwners.isEmpty)
    }

    @Test func externalActivityIsReportedForServerEventAgents() {
        let manager = AgentProcessManager(agents: AgentRegistry([FakeAgentAdapter(activitySource: .serverEvents)]))
        let taskID = UUID()
        manager.runtimeStates[taskID] = .running
        manager.activitySources[taskID] = .serverEvents

        #expect(manager.agentActivity(for: taskID) == nil)
        manager.setExternalActivity(.working, for: taskID)
        #expect(manager.agentActivity(for: taskID) == .working)
        manager.setExternalActivity(.idle, for: taskID)
        #expect(manager.agentActivity(for: taskID) == .idle)
    }

    @Test func ptyTitleAgentsReportNeedsInputFromExternalActivity() {
        let manager = AgentProcessManager(agents: AgentRegistry([FakeAgentAdapter(activitySource: .ptyTitleWithHooks)]))
        let taskID = UUID()
        manager.runtimeStates[taskID] = .running
        manager.activitySources[taskID] = .ptyTitleWithHooks

        manager.setExternalActivity(.needsInput, for: taskID)
        #expect(manager.agentActivity(for: taskID) == .needsInput)
    }

    @Test func ptyTitleAgentsTakeWorkingFromThePty() {
        let manager = AgentProcessManager(agents: AgentRegistry([FakeAgentAdapter(activitySource: .ptyTitleWithHooks)]))
        let taskID = UUID()
        manager.runtimeStates[taskID] = .running
        manager.activitySources[taskID] = .ptyTitleWithHooks

        manager.setExternalActivity(.working, for: taskID)
        #expect(manager.agentActivity(for: taskID) == nil)
    }

    @Test func ptyWorkingClearsNeedsInputForHookAgents() {
        let manager = AgentProcessManager(agents: AgentRegistry([FakeAgentAdapter(activitySource: .ptyTitleWithHooks)]))
        let taskID = UUID()
        manager.runtimeStates[taskID] = .running
        manager.activitySources[taskID] = .ptyTitleWithHooks
        manager.setExternalActivity(.needsInput, for: taskID)

        manager.ptyActivityChanged(.working, taskID: taskID)

        #expect(manager.externalActivity(for: taskID) == nil)
    }

    @Test func ptyWorkingKeepsNeedsInputForServerEventAgents() {
        let manager = AgentProcessManager(agents: AgentRegistry([FakeAgentAdapter(activitySource: .serverEvents)]))
        let taskID = UUID()
        manager.runtimeStates[taskID] = .running
        manager.activitySources[taskID] = .serverEvents
        manager.setExternalActivity(.needsInput, for: taskID)

        manager.ptyActivityChanged(.working, taskID: taskID)

        #expect(manager.externalActivity(for: taskID) == .needsInput)
    }

    @Test func settleIsSuppressedWhileNeedsInputIsPending() {
        let manager = AgentProcessManager(agents: AgentRegistry([FakeAgentAdapter(activitySource: .ptyTitleWithHooks)]))
        let taskID = UUID()
        manager.runtimeStates[taskID] = .running
        manager.activitySources[taskID] = .ptyTitleWithHooks
        var settled: [UUID] = []
        manager.onAgentSettled = { settled.append($0) }
        manager.setExternalActivity(.needsInput, for: taskID)

        manager.agentSettled(taskID: taskID)
        #expect(settled.isEmpty)

        manager.setExternalActivity(nil, for: taskID)
        manager.agentSettled(taskID: taskID)
        #expect(settled == [taskID])
    }

    @Test func externalActivityIsIgnoredForOtherSources() {
        let manager = AgentProcessManager(agents: .pi())
        let taskID = UUID()
        manager.runtimeStates[taskID] = .running
        manager.activitySources[taskID] = .unavailable
        manager.setExternalActivity(.working, for: taskID)

        #expect(manager.agentActivity(for: taskID) == nil)
    }

    @Test func externalActivityIsClearedOnForget() {
        let manager = AgentProcessManager(agents: .pi())
        let taskID = UUID()
        manager.runtimeStates[taskID] = .running
        manager.activitySources[taskID] = .serverEvents
        manager.setExternalActivity(.working, for: taskID)

        manager.forget(taskID: taskID)
        manager.runtimeStates[taskID] = .running
        manager.activitySources[taskID] = .serverEvents

        #expect(manager.agentActivity(for: taskID) == nil)
    }

    @Test func worktreeLaunchesDoNotTakeCurrentTreeLock() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let manager = AgentProcessManager(agents: .pi())
        let first = UUID()
        let second = UUID()

        let firstLock = try manager.acquireCurrentTreeLockIfNeeded(runContext: .worktree, cwd: projectPath, taskID: first, kind: .pi)
        let secondLock = try manager.acquireCurrentTreeLockIfNeeded(runContext: .worktree, cwd: projectPath, taskID: second, kind: .pi)
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
        let manager = AgentProcessManager(agents: .pi())
        let owner = UUID()

        let locked = try manager.acquireCurrentTreeLockIfNeeded(runContext: .current, cwd: projectPath, taskID: owner, kind: .pi)

        #expect(locked == AgentProcessManager.canonicalPath(projectPath))
        #expect(throws: AgentProcessManager.LaunchError.self) {
            try manager.acquireCurrentTreeLockIfNeeded(runContext: .current, cwd: projectPath, taskID: UUID(), kind: .pi)
        }
    }

    @Test func sharedCurrentTreeLaunchDoesNotTakeOrBreakTheLock() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let manager = AgentProcessManager(agents: .pi())
        let owner = UUID()
        _ = try manager.acquireCurrentTreeLockIfNeeded(runContext: .current, cwd: projectPath, taskID: owner, kind: .pi)

        let shared = try manager.acquireCurrentTreeLockIfNeeded(
            runContext: .current, cwd: projectPath, taskID: UUID(), kind: .pi, sharesCurrentTree: true
        )

        #expect(shared == nil)
        #expect(manager.currentTreeOwners[AgentProcessManager.canonicalPath(projectPath)] == owner)
    }

    @Test func sharedLaunchOnFreeTreeTakesTheLock() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let manager = AgentProcessManager(agents: .pi())

        let locked = try manager.acquireCurrentTreeLockIfNeeded(
            runContext: .current, cwd: projectPath, taskID: UUID(), kind: .pi, sharesCurrentTree: true
        )

        #expect(locked == AgentProcessManager.canonicalPath(projectPath))
    }

    @Test func hasActiveCurrentTreeSessionIsFalseByDefault() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let manager = AgentProcessManager(agents: .pi())

        #expect(manager.hasActiveCurrentTreeSession(projectPath: projectPath) == false)
    }

    @Test func hasActiveCurrentTreeSessionIsTrueWhileRunning() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let manager = AgentProcessManager(agents: .pi())
        let taskID = UUID()
        let canonicalPath = AgentProcessManager.canonicalPath(projectPath)
        _ = manager.lock.acquire(path: canonicalPath, taskID: taskID)
        manager.runtimeStates[taskID] = .running

        #expect(manager.hasActiveCurrentTreeSession(projectPath: projectPath) == true)
    }

    @Test func hasActiveCurrentTreeSessionIsFalseAfterExit() throws {
        let projectPath = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectPath) }
        let manager = AgentProcessManager(agents: .pi())
        let taskID = UUID()
        let canonicalPath = AgentProcessManager.canonicalPath(projectPath)
        _ = manager.lock.acquire(path: canonicalPath, taskID: taskID)
        manager.runtimeStates[taskID] = .exited(0)

        #expect(manager.hasActiveCurrentTreeSession(projectPath: projectPath) == false)
    }

    @Test func activeSessionCountCountsStartingRunningAndStopping() {
        let manager = AgentProcessManager(agents: .pi())
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
        let manager = AgentProcessManager(agents: .pi())
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
