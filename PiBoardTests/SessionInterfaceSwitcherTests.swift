import Foundation
import Testing
@testable import PiBoard

@MainActor
struct SessionInterfaceSwitcherTests {
    private static let sessionID = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
    private static let runtimeVersion = "1.0.0"
    private static let shortGracePeriod: TimeInterval = 0.2
    private static let sleepSeconds = "30"

    @MainActor
    private struct Rig {
        let board: BoardModel
        let manager: AgentProcessManager
        let switcher: SessionInterfaceSwitcher
        let driver: FakeConversationDriver
        let adapter: FakeAgentAdapter
        let project: Project
        let directory: URL
        let taskID: UUID

        var task: BoardTask {
            board.tasks.first { $0.id == taskID }!
        }
    }

    private func makeRig(
        hasSession: Bool = true,
        exitsOnShutdown: Bool = true,
        gracePeriod: TimeInterval = ProcessQuitPolicy.gracePeriod,
        terminalExecutable: (path: String, arguments: [String])? = nil
    ) throws -> Rig {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let board = BoardModel(database: database)
        board.addProject(name: "Test", path: directory)
        let project = try #require(board.projects.first)
        board.addTask(title: "Task", prompt: "", to: project.id)
        let taskID = try #require(board.tasks.first).id
        if hasSession { board.setSessionID(Self.sessionID, for: taskID) }

        let command = AgentLaunchCommand(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], currentDirectory: directory)
        let terminalCommand = terminalExecutable.map {
            AgentLaunchCommand(executable: URL(fileURLWithPath: $0.path), arguments: $0.arguments, currentDirectory: directory)
        }
        let adapter = FakeAgentAdapter(
            launchResult: terminalCommand.map { .success(($0, Self.runtimeVersion)) } ?? .failure(AgentAdapterError.runtimeNotReady),
            conversationLaunchResult: .success((command, Self.runtimeVersion)),
            sessionExistsResult: true
        )
        let driver = FakeConversationDriver()
        driver.exitsOnShutdown = exitsOnShutdown
        let agents = AgentRegistry([adapter])
        let manager = AgentProcessManager(makeConversation: { _ in ConversationSession(driver: driver) }, agents: agents)
        let resumer = AgentSessionResumer(processes: manager, worktrees: FakeWorktreeService(), agents: agents)
        let switcher = SessionInterfaceSwitcher(board: board, processes: manager, resumer: resumer, gracePeriod: gracePeriod)
        return Rig(board: board, manager: manager, switcher: switcher, driver: driver, adapter: adapter, project: project, directory: directory, taskID: taskID)
    }

    @Test func stopsTheRunningChatThenResumesInTheTerminal() async throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.board.setInterface(.chat, for: rig.taskID)
        _ = try rig.manager.resumeConversation(
            task: rig.task, project: rig.project, runContext: .current, cwd: rig.directory, sessionID: Self.sessionID
        )

        _ = await rig.switcher.switchInterface(task: rig.task, project: rig.project, to: .terminal, sharesCurrentTree: false)

        #expect(rig.driver.calls.contains(.shutdown))
        #expect(!rig.driver.calls.contains(.forceKill))
        #expect(rig.task.interface == .terminal)
        #expect(rig.adapter.launches == [.resume(sessionID: Self.sessionID)])
    }

    @Test func resumesInChatWithoutStoppingAnIdleTask() async throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        let outcome = await rig.switcher.switchInterface(task: rig.task, project: rig.project, to: .chat, sharesCurrentTree: false)

        #expect(outcome == .started)
        #expect(rig.task.interface == .chat)
        #expect(rig.adapter.conversationLaunches == [.resume(sessionID: Self.sessionID)])
        #expect(rig.driver.calls == [.start])
        #expect(rig.manager.conversation(for: rig.taskID) != nil)
    }

    @Test func recordsTheInterfaceAndLaunchesNothingWithoutASession() async throws {
        let rig = try makeRig(hasSession: false)
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        let outcome = await rig.switcher.switchInterface(task: rig.task, project: rig.project, to: .chat, sharesCurrentTree: false)

        #expect(outcome == nil)
        #expect(rig.task.interface == .chat)
        #expect(rig.adapter.conversationLaunches.isEmpty)
        #expect(rig.driver.calls.isEmpty)
    }

    @Test func forceKillsAProcessThatIgnoresTheStop() async throws {
        let rig = try makeRig(exitsOnShutdown: false, gracePeriod: Self.shortGracePeriod)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.board.setInterface(.chat, for: rig.taskID)
        _ = try rig.manager.resumeConversation(
            task: rig.task, project: rig.project, runContext: .current, cwd: rig.directory, sessionID: Self.sessionID
        )

        _ = await rig.switcher.switchInterface(task: rig.task, project: rig.project, to: .terminal, sharesCurrentTree: false)

        #expect(rig.driver.calls.contains(.shutdown))
        #expect(rig.driver.calls.contains(.forceKill))
        #expect(rig.adapter.launches == [.resume(sessionID: Self.sessionID)])
    }

    @Test func keepsTheSessionIDAndTheLockAfterAResume() async throws {
        let rig = try makeRig(terminalExecutable: ("/bin/sleep", [Self.sleepSeconds]))
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        rig.board.setInterface(.chat, for: rig.taskID)
        _ = try rig.manager.resumeConversation(
            task: rig.task, project: rig.project, runContext: .current, cwd: rig.directory, sessionID: Self.sessionID
        )

        _ = await rig.switcher.switchInterface(task: rig.task, project: rig.project, to: .terminal, sharesCurrentTree: false)

        #expect(rig.task.sessionID == Self.sessionID)
        #expect(rig.manager.currentTreeOwners.values.contains(rig.taskID))
        rig.manager.stopAll()
    }

    @Test func switchesFromALivePTYSessionToChat() async throws {
        let rig = try makeRig(terminalExecutable: ("/bin/sleep", [Self.sleepSeconds]))
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        _ = try rig.manager.resume(
            task: rig.task, project: rig.project, runContext: .current, cwd: rig.directory, sessionID: Self.sessionID
        )
        try #require(rig.manager.session(for: rig.taskID) != nil)

        let outcome = await rig.switcher.switchInterface(task: rig.task, project: rig.project, to: .chat, sharesCurrentTree: false)

        #expect(outcome == .started)
        #expect(rig.task.interface == .chat)
        #expect(rig.task.sessionID == Self.sessionID)
        #expect(rig.adapter.conversationLaunches == [.resume(sessionID: Self.sessionID)])
        #expect(rig.manager.conversation(for: rig.taskID) != nil)
        #expect(rig.manager.currentTreeOwners.values.contains(rig.taskID))
    }

    @Test func failsWithoutWritingTheInterfaceWhenTheRuntimeStaysActive() async throws {
        let rig = try makeRig(gracePeriod: Self.shortGracePeriod)
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        // No process behind the state, so neither stop nor kill can clear it.
        rig.manager.runtimeStates[rig.taskID] = .running

        let outcome = await rig.switcher.switchInterface(task: rig.task, project: rig.project, to: .chat, sharesCurrentTree: false)

        #expect(outcome == .failed(SessionInterfaceSwitcher.stillRunningMessage))
        #expect(rig.task.interface == SessionInterface.default)
        #expect(rig.adapter.conversationLaunches.isEmpty)
    }

    @Test func passesSharesCurrentTreeToTheResumer() async throws {
        let rig = try makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        let owner = UUID()
        _ = try rig.manager.acquireCurrentTreeLockIfNeeded(runContext: .current, cwd: rig.directory, taskID: owner, kind: .default)

        let blocked = await rig.switcher.switchInterface(task: rig.task, project: rig.project, to: .chat, sharesCurrentTree: false)
        let shared = await rig.switcher.switchInterface(task: rig.task, project: rig.project, to: .chat, sharesCurrentTree: true)

        #expect(blocked == .currentTreeBusy(ownerTaskID: owner))
        #expect(shared == .started)
    }
}
