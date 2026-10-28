import Foundation
import Testing
@testable import PiBoard

@MainActor
struct PiAgentTests {
    private let cwd = URL(fileURLWithPath: "/tmp/piagent-project")
    private let entry = URL(fileURLWithPath: "/tmp/piagent-runtime/pi.js")
    private let node = BundledNode(
        nodeExecutable: URL(fileURLWithPath: "/tmp/piagent-node/bin/node"),
        npmCLI: URL(fileURLWithPath: "/tmp/piagent-node/npm-cli.js")
    )

    @Test func makeSessionIDIsAUUID() {
        let agent = PiAgent(runtime: { throw PiRuntimeManagerError.noActiveVersion })

        #expect(UUID(uuidString: agent.makeSessionID()) != nil)
    }

    @Test func launchCommandRejectsANonUUID() {
        let agent = makeAgent()

        #expect(throws: AgentAdapterError.invalidSessionID("not-a-uuid")) {
            try agent.launchCommand(mode: .resume(sessionID: "not-a-uuid"), cwd: cwd)
        }
    }

    @Test func launchCommandMapsMissingRuntime() {
        let agent = PiAgent(runtime: { throw PiRuntimeManagerError.noActiveVersion }, locateNode: { [node] in node })

        #expect(throws: AgentAdapterError.runtimeNotReady) {
            try agent.launchCommand(mode: .resume(sessionID: UUID().uuidString), cwd: cwd)
        }
    }

    @Test func launchCommandBuildsTheResumeArguments() throws {
        let agent = makeAgent()
        let id = UUID().uuidString

        let launch = try agent.launchCommand(mode: .resume(sessionID: id), cwd: cwd)

        #expect(launch.command.arguments == [entry.path, "--session", id])
        #expect(launch.command.executable == node.nodeExecutable)
        #expect(launch.command.currentDirectory == cwd)
        #expect(launch.runtimeVersion == "1.2.3")
    }

    @Test func launchCommandUsesTheRuntimeEntry() throws {
        let fakeRuntime = FakeAgentRuntime(status: .ready(version: "1.2.3"), entry: entry)
        let node = node
        let agent = PiAgent(runtime: { try fakeRuntime.activeEntry() }, locateNode: { node })

        let launch = try agent.launchCommand(mode: .resume(sessionID: UUID().uuidString), cwd: cwd)

        #expect(launch.runtimeVersion == "1.2.3")
        #expect(launch.command.arguments.first == entry.path)
    }

    @Test func launchCommandFailsWhenTheFakeRuntimeIsMissing() {
        let fakeRuntime = FakeAgentRuntime(status: .missing)
        let node = node
        let agent = PiAgent(runtime: { try fakeRuntime.activeEntry() }, locateNode: { node })

        #expect(throws: AgentAdapterError.runtimeNotReady) {
            try agent.launchCommand(mode: .resume(sessionID: UUID().uuidString), cwd: cwd)
        }
    }

    @Test func sessionExistsIsNilWithoutASessionsDirectory() throws {
        let agentDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let agent = PiAgent(agentDirectory: agentDir, runtime: { throw PiRuntimeManagerError.noActiveVersion })

        #expect(agent.sessionExists(id: UUID().uuidString, cwd: cwd) == nil)
    }

    private func makeAgent() -> PiAgent {
        let entry = entry
        let node = node
        return PiAgent(runtime: { ("1.2.3", entry) }, locateNode: { node })
    }
}
