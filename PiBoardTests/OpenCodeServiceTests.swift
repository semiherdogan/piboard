import Foundation
import Synchronization
import Testing
@testable import PiBoard

struct OpenCodeServiceTests {
    private static let password = "pw"
    private static let discoveryDelay: TimeInterval = 0.05

    private final class CountingRunner: CommandRunning, @unchecked Sendable {
        private struct State {
            var arguments: [[String]] = []
            var statusOutput: String
        }

        private let state: Mutex<State>

        init(statusOutput: String) {
            state = Mutex(State(statusOutput: statusOutput))
        }

        var statusCalls: Int {
            state.withLock { $0.arguments.filter { $0 == OpenCodeServiceLocator.statusArguments }.count }
        }

        func setStatusOutput(_ output: String) {
            state.withLock { $0.statusOutput = output }
        }

        func run(
            executable: URL,
            arguments: [String],
            environment: [String: String],
            timeout: Duration?,
            cancellation: CommandCancellation?
        ) -> CommandResult? {
            // Keeps concurrent callers overlapping inside discovery.
            Thread.sleep(forTimeInterval: OpenCodeServiceTests.discoveryDelay)
            let stdout = state.withLock { state -> String in
                state.arguments.append(arguments)
                return arguments == OpenCodeServiceLocator.statusArguments ? state.statusOutput : ""
            }
            return CommandResult(exitCode: 0, stdout: stdout, stderr: "", timedOut: false)
        }
    }

    private struct Fixture {
        let service: OpenCodeService
        let runner: CountingRunner
        let host: String
    }

    private func makeFixture(statusOutput: String? = nil) throws -> Fixture {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"password":"\#(Self.password)"}"#.utf8)
            .write(to: directory.appendingPathComponent(OpenCodeServiceLocator.configFileName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let runner = CountingRunner(statusOutput: statusOutput ?? "http://\(host)")
        let service = OpenCodeService(
            executable: { URL(fileURLWithPath: "/opt/opencode") },
            runner: runner,
            environment: [:],
            configDirectory: directory,
            urlSession: URLSession(configuration: configuration)
        )
        return Fixture(service: service, runner: runner, host: host)
    }

    @Test func concurrentFirstCallsDiscoverOnce() async throws {
        let fixture = try makeFixture()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { _ = try await fixture.service.client() }
            }
            try await group.waitForAll()
        }
        #expect(fixture.runner.statusCalls == 1)
    }

    @Test func connectionFailureInvalidatesAndRetriesOnce() async throws {
        let fixture = try makeFixture()
        StubURLProtocol.register(host: fixture.host) { _ in .json(200, #"{"data":{"ses_a":{}}}"#) }
        let attempts = Mutex(0)

        let active = try await fixture.service.withClient { client in
            let attempt = attempts.withLock { count -> Int in
                count += 1
                return count
            }
            // The stub cannot fail a request, so the first attempt fails the way a stale port would.
            if attempt == 1 { throw URLError(.cannotConnectToHost) }
            return try await client.activeSessionIDs()
        }

        #expect(active == ["ses_a"])
        #expect(attempts.withLock { $0 } == 2)
        #expect(fixture.runner.statusCalls == 2)
    }

    @Test func failedDiscoveryIsRetriedOnTheNextCall() async throws {
        let fixture = try makeFixture(statusOutput: "")
        await #expect(throws: OpenCodeService.Failure.serviceUnavailable) {
            _ = try await fixture.service.client()
        }
        let failedCalls = fixture.runner.statusCalls

        fixture.runner.setStatusOutput("http://\(fixture.host)")
        _ = try await fixture.service.client()

        #expect(fixture.runner.statusCalls == failedCalls + 1)
    }
}
