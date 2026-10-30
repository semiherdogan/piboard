import Foundation
import Testing
@testable import PiBoard

private struct ServiceStatusRunner: CommandRunning {
    let output: String

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

struct OpenCodeCommitMessageGeneratorTests {
    private static let context = CommitPromptContext(diff: "the diff", branch: "main", recentSubjects: [])
    private static let generateSuffix = "/generate"
    private static let sessionJSON = """
    {"id":"ses_abc","title":"t","tokens":{"input":0,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},\
    "cost":0,"time":{"created":1,"updated":2},"location":{"directory":"/tmp"}}
    """

    private struct Harness {
        let generator: OpenCodeCommitMessageGenerator
        let host: String
    }

    /// Each test gets its own host so parallel tests never share stub state.
    private func makeHarness(generate: @escaping @Sendable () -> StubResponse) throws -> Harness {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        let configDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try Data(#"{"password":"pw"}"#.utf8).write(to: configDirectory.appendingPathComponent(OpenCodeServiceLocator.configFileName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let binary = URL(fileURLWithPath: "/tmp/opencode-bin/opencode")
        let service = OpenCodeService(
            executable: { binary },
            runner: ServiceStatusRunner(output: "http://\(host)\n"),
            environment: [:],
            configDirectory: configDirectory,
            urlSession: URLSession(configuration: configuration)
        )
        StubURLProtocol.register(host: host) { request in
            if request.method == "POST", request.path.hasSuffix(Self.generateSuffix) {
                return generate()
            }
            if request.method == "DELETE" {
                return .json(204, "")
            }
            return .json(200, #"{"data":\#(Self.sessionJSON)}"#)
        }
        return Harness(generator: OpenCodeCommitMessageGenerator(service: service), host: host)
    }

    @Test func createsGeneratesAndDeletesTheSessionInOrder() async throws {
        let harness = try makeHarness { .json(200, #"{"data":{"text":"- feat: thing\n"}}"#) }

        let message = try await harness.generator.generate(Self.context)

        #expect(message == "feat: thing")
        let requests = StubURLProtocol.requests(host: harness.host)
        #expect(requests.map(\.method) == ["POST", "POST", "DELETE"])
        let id = try #require(requests.last?.path.split(separator: "/").last.map(String.init))
        #expect(OpenCodeClient.isValidSessionID(id))
        #expect(requests.map(\.path) == [
            "/api/session",
            "/api/session/\(id)/generate",
            "/api/session/\(id)",
        ])
    }

    @Test func aFailingGenerateStillDeletesTheSession() async throws {
        let harness = try makeHarness { .json(500, "broken") }

        await #expect(throws: CommitMessageGeneratorError.failed(OpenCodeClientError.http(status: 500, body: "broken").localizedDescription)) {
            try await harness.generator.generate(Self.context)
        }

        let requests = StubURLProtocol.requests(host: harness.host)
        #expect(requests.map(\.method) == ["POST", "POST", "DELETE"])
    }

    @Test func emptyTextIsEmptyResponse() async throws {
        let harness = try makeHarness { .json(200, #"{"data":{"text":"  "}}"#) }

        await #expect(throws: CommitMessageGeneratorError.emptyResponse(agent: .opencode)) {
            try await harness.generator.generate(Self.context)
        }
    }
}
