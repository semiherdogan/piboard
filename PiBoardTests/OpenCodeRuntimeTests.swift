import Testing
@testable import PiBoard
import Foundation
import Synchronization

@MainActor
struct OpenCodeRuntimeTests {
    private let versionOutput = "opencode v2.2.0\n"

    @Test func refreshReportsReadyWithTheVersion() async throws {
        let directory = try makeDirectory(withExecutable: true)
        let runtime = makeRuntime(directory: directory, runner: StubRunner { CommandResult(exitCode: 0, stdout: versionOutput, stderr: "", timedOut: false) })

        runtime.refresh()
        await runtime.refreshTask?.value

        #expect(runtime.status == .ready(version: "2.2.0"))
        #expect(runtime.activeVersion == "2.2.0")
        #expect(runtime.executable == directory.appendingPathComponent("opencode"))
        #expect(!runtime.isRefreshing)
    }

    @Test func refreshReportsMissingWithoutAnExecutable() async throws {
        let directory = try makeDirectory(withExecutable: false)
        let runner = StubRunner { Issue.record("nothing should run without an executable"); return nil }
        let runtime = makeRuntime(directory: directory, runner: runner)

        runtime.refresh()
        await runtime.refreshTask?.value

        #expect(runtime.status == .missing)
        #expect(runtime.activeVersion == nil)
        #expect(runtime.executable == nil)
        #expect(runner.callCount == 0)
    }

    @Test func refreshReportsMissingWhenVersionFails() async throws {
        let directory = try makeDirectory(withExecutable: true)
        let runtime = makeRuntime(directory: directory, runner: StubRunner { CommandResult(exitCode: 1, stdout: "", stderr: "boom", timedOut: false) })

        runtime.refresh()
        await runtime.refreshTask?.value

        #expect(runtime.status == .missing)
        #expect(runtime.activeVersion == nil)
        #expect(runtime.executable == nil)
    }

    @Test func activeEntryThrowsUntilReady() async throws {
        let directory = try makeDirectory(withExecutable: true)
        let runtime = makeRuntime(directory: directory, runner: StubRunner { CommandResult(exitCode: 0, stdout: versionOutput, stderr: "", timedOut: false) })

        #expect(throws: PiRuntimeManagerError.noActiveVersion) { try runtime.activeEntry() }

        runtime.refresh()
        await runtime.refreshTask?.value

        let active = try runtime.activeEntry()
        #expect(active.version == "2.2.0")
        #expect(active.entry == directory.appendingPathComponent("opencode"))
    }

    @Test func secondRefreshWhileRunningIsIgnored() async throws {
        let directory = try makeDirectory(withExecutable: true)
        let gate = DispatchSemaphore(value: 0)
        let runner = StubRunner {
            gate.wait()
            return CommandResult(exitCode: 0, stdout: "2.2.0", stderr: "", timedOut: false)
        }
        let runtime = makeRuntime(directory: directory, runner: runner)

        runtime.refresh()
        #expect(runtime.isRefreshing)
        runtime.refresh()
        gate.signal()
        await runtime.refreshTask?.value

        #expect(runner.callCount == 1)
        #expect(runtime.status == .ready(version: "2.2.0"))
    }

    private func makeRuntime(directory: URL, runner: StubRunner) -> OpenCodeRuntime {
        OpenCodeRuntime(runner: runner, environment: ["PATH": directory.path], homeDirectory: directory)
    }

    private func makeDirectory(withExecutable: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("piboard-opencode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if withExecutable {
            let file = directory.appendingPathComponent("opencode")
            try Data().write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        return directory
    }
}

private final class StubRunner: CommandRunning, Sendable {
    private let handler: @Sendable () -> CommandResult?
    private let calls = Mutex(0)

    init(handler: @escaping @Sendable () -> CommandResult?) {
        self.handler = handler
    }

    var callCount: Int { calls.withLock { $0 } }

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?,
        cancellation: CommandCancellation?
    ) -> CommandResult? {
        calls.withLock { $0 += 1 }
        return handler()
    }
}
