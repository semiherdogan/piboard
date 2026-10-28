import Foundation
import Testing
@testable import PiBoard

@MainActor
struct OpenCodeAgentTests {
    private let cwd = URL(fileURLWithPath: "/tmp/opencode-project")
    private let binary = URL(fileURLWithPath: "/tmp/opencode-bin/opencode")
    private let password = "pw"
    private let sessionJSON = """
    {"id":"ses_abc","title":"Task","tokens":{"input":1,"output":2,"reasoning":3,"cache":{"read":4,"write":5}},\
    "cost":0.5,"time":{"created":1000,"updated":2000},"location":{"directory":"/tmp/opencode-project"}}
    """

    private struct Harness {
        let agent: OpenCodeAgent
        let host: String
        let configDirectory: URL
    }

    /// Each test gets its own host so parallel tests never share stub state.
    private func makeHarness(password: String? = nil) throws -> Harness {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        let configDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try Self.writePassword(password ?? self.password, to: configDirectory)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let runner = StatusRunner(output: "http://\(host)\n")
        let binary = binary
        let service = OpenCodeService(
            executable: { binary },
            runner: runner,
            environment: [:],
            configDirectory: configDirectory,
            urlSession: URLSession(configuration: configuration)
        )
        let entry = binary
        let agent = OpenCodeAgent(service: service, runtime: { ("2.2.0", entry) })
        return Harness(agent: agent, host: host, configDirectory: configDirectory)
    }

    private nonisolated static func writePassword(_ password: String, to directory: URL) throws {
        let body = Data(#"{"password":"\#(password)"}"#.utf8)
        try body.write(to: directory.appendingPathComponent(OpenCodeServiceLocator.configFileName))
    }

    @Test func makeSessionIDHasThePrefix() throws {
        let agent = try makeHarness().agent

        #expect(agent.makeSessionID().hasPrefix(OpenCodeClient.sessionIDPrefix))
    }

    @Test func launchCommandUsesSessionPromptAndDirectory() throws {
        let agent = try makeHarness().agent
        let id = OpenCodeClient.makeSessionID()

        let launch = try agent.launchCommand(mode: .newSession(sessionID: id, name: "Task", initialPrompt: "do it"), cwd: cwd)

        #expect(launch.command.arguments == [OpenCodeAgent.sessionFlag, id, OpenCodeAgent.promptFlag, "do it", cwd.path])
        #expect(launch.command.executable == binary)
        #expect(launch.command.currentDirectory == cwd)
        #expect(launch.runtimeVersion == "2.2.0")
    }

    @Test func launchCommandOmitsThePromptWhenThereIsNone() throws {
        let agent = try makeHarness().agent
        let id = OpenCodeClient.makeSessionID()

        let fresh = try agent.launchCommand(mode: .newSession(sessionID: id, name: nil, initialPrompt: nil), cwd: cwd)
        let resumed = try agent.launchCommand(mode: .resume(sessionID: id), cwd: cwd)

        #expect(fresh.command.arguments == [OpenCodeAgent.sessionFlag, id, cwd.path])
        #expect(resumed.command.arguments == fresh.command.arguments)
    }

    @Test func launchCommandRejectsForeignIDs() throws {
        let agent = try makeHarness().agent
        let foreign = UUID().uuidString

        #expect(throws: AgentAdapterError.invalidSessionID(foreign)) {
            try agent.launchCommand(mode: .resume(sessionID: foreign), cwd: cwd)
        }
    }

    @Test func launchCommandMapsMissingRuntime() {
        let service = OpenCodeService(executable: { nil })
        let agent = OpenCodeAgent(service: service, runtime: { throw PiRuntimeManagerError.noActiveVersion })

        #expect(throws: AgentAdapterError.runtimeNotReady) {
            try agent.launchCommand(mode: .resume(sessionID: OpenCodeClient.makeSessionID()), cwd: cwd)
        }
    }

    @Test func prepareSessionPostsToTheServer() async throws {
        let harness = try makeHarness()
        let sessionJSON = sessionJSON
        StubURLProtocol.register(host: harness.host) { _ in .json(200, #"{"data":\#(sessionJSON)}"#) }

        try await harness.agent.prepareSession(id: "ses_abc", title: "Task", cwd: cwd)

        let request = try #require(StubURLProtocol.requests(host: harness.host).first)
        #expect(request.method == "POST")
        #expect(request.path == "/api/session")
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["id"] as? String == "ses_abc")
        #expect(body["title"] as? String == "Task")
        #expect((body["location"] as? [String: Any])?["directory"] as? String == cwd.path)
    }

    @Test func prepareSessionReportsAnUnreachableServer() async throws {
        let harness = try makeHarness()
        StubURLProtocol.register(host: harness.host) { _ in .json(500, "boom") }

        let expected = OpenCodeClientError.http(status: 500, body: "boom").localizedDescription
        await #expect(throws: AgentAdapterError.serviceUnavailable(detail: expected)) {
            try await harness.agent.prepareSession(id: "ses_abc", title: "Task", cwd: cwd)
        }
    }

    @Test func prepareSessionReportsAMissingInstall() async {
        let agent = OpenCodeAgent(service: OpenCodeService(executable: { nil }), runtime: { throw PiRuntimeManagerError.noActiveVersion })

        let expected = OpenCodeService.Failure.notInstalled.localizedDescription
        await #expect(throws: AgentAdapterError.serviceUnavailable(detail: expected)) {
            try await agent.prepareSession(id: "ses_abc", title: "Task", cwd: cwd)
        }
    }

    @Test func sessionExistsReadsTheServer() async throws {
        let harness = try makeHarness()
        let sessionJSON = sessionJSON
        StubURLProtocol.register(host: harness.host) { _ in .json(200, #"{"data":\#(sessionJSON)}"#) }
        #expect(await harness.agent.sessionExists(id: "ses_abc", cwd: cwd) == true)

        StubURLProtocol.register(host: harness.host) { _ in .json(200, #"{"_tag":"SessionNotFoundError"}"#) }
        #expect(await harness.agent.sessionExists(id: "ses_abc", cwd: cwd) == false)

        StubURLProtocol.register(host: harness.host) { _ in .json(500, "boom") }
        #expect(await harness.agent.sessionExists(id: "ses_abc", cwd: cwd) == nil)
    }

    @Test func plannedSessionRemovalShortensTheID() throws {
        let agent = try makeHarness().agent

        #expect(agent.plannedSessionRemoval(id: "ses_0123456789abcdef", cwd: cwd) == "OpenCode session ses_01234567")
    }

    @Test func deleteSessionCallsDelete() async throws {
        let harness = try makeHarness()
        StubURLProtocol.register(host: harness.host) { _ in .json(204, "") }

        try await harness.agent.deleteSession(id: "ses_abc", cwd: cwd)

        let request = try #require(StubURLProtocol.requests(host: harness.host).first)
        #expect(request.method == "DELETE")
        #expect(request.path == "/api/session/ses_abc")
    }

    @Test func summaryMapsTokensAndCost() async throws {
        let harness = try makeHarness()
        let sessionJSON = sessionJSON
        StubURLProtocol.register(host: harness.host) { request in
            if request.path.hasSuffix("/message") {
                return .json(200, #"{"data":[{"id":"m","time":{"created":10},"type":"assistant","content":[{"type":"text","text":"done"}]}]}"#)
            }
            return .json(200, #"{"data":\#(sessionJSON)}"#)
        }

        let summary = try #require(await harness.agent.readSessionSummary(id: "ses_abc", cwd: cwd))

        #expect(summary.name == "Task")
        #expect(summary.lastAssistantText == "done")
        #expect(summary.usage == SessionSummary.Usage(input: 1, output: 2, cacheRead: 4, cacheWrite: 5, total: 15, cost: 0.5))
        #expect(summary.lastActivity == Date(timeIntervalSince1970: 2))
    }

    @Test func summaryIsNilForAMissingSession() async throws {
        let harness = try makeHarness()
        StubURLProtocol.register(host: harness.host) { _ in .json(404, #"{"_tag":"SessionNotFoundError"}"#) }

        #expect(await harness.agent.readSessionSummary(id: "ses_abc", cwd: cwd) == nil)
    }

    @Test func unauthorizedIsRetriedOnceWithAFreshPassword() async throws {
        let harness = try makeHarness(password: "old")
        let configDirectory = harness.configDirectory
        let sessionJSON = sessionJSON
        let host = harness.host
        // The stub records a request before it calls the handler, so the count is this call's number.
        StubURLProtocol.register(host: host) { _ in
            guard StubURLProtocol.requests(host: host).count > 1 else {
                try? Self.writePassword("new", to: configDirectory)
                return .json(401, #"{"_tag":"UnauthorizedError"}"#)
            }
            return .json(200, #"{"data":\#(sessionJSON)}"#)
        }

        #expect(await harness.agent.sessionExists(id: "ses_abc", cwd: cwd) == true)

        let requests = StubURLProtocol.requests(host: harness.host)
        #expect(requests.count == 2)
        let auth = { (password: String) in "Basic " + Data("opencode:\(password)".utf8).base64EncodedString() }
        #expect(requests.first?.authorization == auth("old"))
        #expect(requests.last?.authorization == auth("new"))
    }
}

private final class StatusRunner: CommandRunning, Sendable {
    private let output: String

    init(output: String) {
        self.output = output
    }

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?,
        cancellation: CommandCancellation?
    ) -> CommandResult? {
        CommandResult(exitCode: 0, stdout: output, stderr: "", timedOut: false)
    }
}
