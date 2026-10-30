import Foundation
import Testing
@testable import PiBoard

@MainActor
struct ClaudeCodeAgentTests {
    private let cwd = URL(fileURLWithPath: "/nonexistent-root/claude-project")
    private let entry = URL(fileURLWithPath: "/tmp/claude-runtime/claude")
    private let version = "2.1.294"
    private let sessionID = "0b0c7f0e-1c2d-4e5f-8a9b-0c1d2e3f4a5b"

    @Test func newSessionPassesIDNameAndPromptLastAfterEndOfOptions() throws {
        let launch = try makeAgent().launchCommand(mode: .newSession(sessionID: sessionID, name: "Task", initialPrompt: "Fix it"), cwd: cwd)

        #expect(launch.command == AgentLaunchCommand(
            executable: entry,
            arguments: [ClaudeCodeAgent.sessionIDFlag, sessionID, ClaudeCodeAgent.nameFlag, "Task", ClaudeCodeAgent.endOfOptions, "Fix it"],
            currentDirectory: cwd
        ))
        #expect(launch.runtimeVersion == version)
    }

    @Test func aPromptStartingWithADashLandsAfterEndOfOptions() throws {
        let launch = try makeAgent().launchCommand(mode: .newSession(sessionID: sessionID, name: nil, initialPrompt: "-fix it"), cwd: cwd)

        #expect(launch.command.arguments == [ClaudeCodeAgent.sessionIDFlag, sessionID, ClaudeCodeAgent.endOfOptions, "-fix it"])
    }

    @Test func hooksThatWereNeverStartedAddNoSettings() throws {
        let agent = makeAgent(hooks: ClaudeCodeHooks(server: FakeHookServer()))

        let fresh = try agent.launchCommand(mode: .newSession(sessionID: sessionID, name: "Task", initialPrompt: "Fix it"), cwd: cwd)
        let resumed = try agent.launchCommand(mode: .resume(sessionID: sessionID), cwd: cwd)

        #expect(!fresh.command.arguments.contains(ClaudeCodeAgent.settingsFlag))
        #expect(resumed.command.arguments == [ClaudeCodeAgent.resumeFlag, sessionID])
    }

    @Test func newSessionWithoutNameOrPrompt() throws {
        let launch = try makeAgent().launchCommand(mode: .newSession(sessionID: sessionID, name: nil, initialPrompt: nil), cwd: cwd)

        #expect(launch.command.arguments == [ClaudeCodeAgent.sessionIDFlag, sessionID])
    }

    @Test func resumePassesTheID() throws {
        let launch = try makeAgent().launchCommand(mode: .resume(sessionID: sessionID), cwd: cwd)

        #expect(launch.command.arguments == [ClaudeCodeAgent.resumeFlag, sessionID])
    }

    @Test func hooksSettingsGoAfterTheSessionFlagsAndBeforeThePrompt() async throws {
        let hooks = ClaudeCodeHooks(server: FakeHookServer())
        let agent = makeAgent(hooks: hooks)
        try await agent.prepareSession(id: sessionID, title: "Task", cwd: cwd)

        let fresh = try agent.launchCommand(mode: .newSession(sessionID: sessionID, name: "Task", initialPrompt: "Fix it"), cwd: cwd)
        let resumed = try agent.launchCommand(mode: .resume(sessionID: sessionID), cwd: cwd)

        let freshJSON = try #require(fresh.command.arguments.dropLast(2).last)
        #expect(fresh.command.arguments == [
            ClaudeCodeAgent.sessionIDFlag, sessionID, ClaudeCodeAgent.nameFlag, "Task", ClaudeCodeAgent.settingsFlag, freshJSON,
            ClaudeCodeAgent.endOfOptions, "Fix it",
        ])
        #expect(freshJSON.contains(ClaudeCodeHooks.pathPrefix))
        let resumedJSON = try #require(resumed.command.arguments.last)
        #expect(resumed.command.arguments == [ClaudeCodeAgent.resumeFlag, sessionID, ClaudeCodeAgent.settingsFlag, resumedJSON])
        #expect(resumedJSON.contains(ClaudeCodeHooks.pathPrefix))
    }

    @Test func launchRejectsANonUUID() {
        #expect(throws: AgentAdapterError.invalidSessionID("not-a-uuid")) {
            try makeAgent().launchCommand(mode: .resume(sessionID: "not-a-uuid"), cwd: cwd)
        }
    }

    @Test func missingRuntimeMapsToRuntimeNotReady() {
        let agent = ClaudeCodeAgent(runtime: { throw PiRuntimeManagerError.noActiveVersion })

        #expect(throws: AgentAdapterError.runtimeNotReady) {
            try agent.launchCommand(mode: .resume(sessionID: sessionID), cwd: cwd)
        }
    }

    @Test func makeSessionIDIsALowercaseUUID() {
        let id = makeAgent().makeSessionID()

        #expect(UUID(uuidString: id) != nil)
        #expect(id == id.lowercased())
    }

    @Test func sessionExistsIsNilWithoutAProjectsDirectory() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("piboard-claude-\(UUID().uuidString)")

        #expect(await makeAgent(projects: missing).sessionExists(id: sessionID, cwd: cwd) == nil)
    }

    @Test func sessionExistsReflectsTheFile() async throws {
        let projects = try makeProjects()
        defer { try? FileManager.default.removeItem(at: projects) }
        let agent = makeAgent(projects: projects)

        #expect(await agent.sessionExists(id: sessionID, cwd: cwd) == false)
        try writeSession(in: projects)
        #expect(await agent.sessionExists(id: sessionID, cwd: cwd) == true)
    }

    @Test func plannedRemovalNamesTheFileOnlyWhenPresent() throws {
        let projects = try makeProjects()
        defer { try? FileManager.default.removeItem(at: projects) }
        let agent = makeAgent(projects: projects)

        #expect(agent.plannedSessionRemoval(id: sessionID, cwd: cwd) == nil)
        try writeSession(in: projects)
        #expect(agent.plannedSessionRemoval(id: sessionID, cwd: cwd) != nil)
    }

    @Test func deleteSessionRemovesTheFile() async throws {
        let projects = try makeProjects()
        defer { try? FileManager.default.removeItem(at: projects) }
        let file = try writeSession(in: projects)

        try await makeAgent(projects: projects).deleteSession(id: sessionID, cwd: cwd)

        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func deleteSessionWithoutAFileDoesNothing() async throws {
        let projects = try makeProjects()
        defer { try? FileManager.default.removeItem(at: projects) }

        try await makeAgent(projects: projects).deleteSession(id: sessionID, cwd: cwd)
    }

    @Test func readSessionSummaryReturnsTheName() async throws {
        let projects = try makeProjects()
        defer { try? FileManager.default.removeItem(at: projects) }
        try writeSession(in: projects, contents: #"{"type":"custom-title","customTitle":"spike"}"#)

        let summary = await makeAgent(projects: projects).readSessionSummary(id: sessionID, cwd: cwd)

        #expect(summary?.name == "spike")
    }

    @Test func readSessionTranscriptReadsTheFileAndIsNilWhenMissing() async throws {
        let projects = try makeProjects()
        defer { try? FileManager.default.removeItem(at: projects) }
        let agent = makeAgent(projects: projects)
        #expect(await agent.readSessionTranscript(id: sessionID, cwd: cwd) == nil)
        try writeSession(in: projects, contents: #"{"type":"user","message":{"role":"user","content":"Hello"}}"#)

        let transcript = await agent.readSessionTranscript(id: sessionID, cwd: cwd)

        #expect(transcript?.messages.map(\.text) == ["Hello"])
    }

    private func makeAgent(projects: URL? = nil, hooks: ClaudeCodeHooks? = nil) -> ClaudeCodeAgent {
        let entry = entry
        let version = version
        return ClaudeCodeAgent(
            projectsDirectory: projects ?? FileManager.default.temporaryDirectory.appendingPathComponent("piboard-claude-unused"),
            hooks: hooks,
            runtime: { (version, entry) }
        )
    }

    private func makeProjects() throws -> URL {
        let projects = FileManager.default.temporaryDirectory.appendingPathComponent("piboard-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        return projects
    }

    @discardableResult
    private func writeSession(in projects: URL, contents: String = "") throws -> URL {
        let folder = projects.appendingPathComponent(ClaudeSessionLocator.encodedProjectName(cwd: cwd), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(sessionID).jsonl")
        try Data(contents.utf8).write(to: file)
        return file
    }
}
