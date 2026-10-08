import Foundation
import Testing
@testable import PiBoard

struct PiExtensionUpdaterTests {
    private let node = BundledNode(
        nodeExecutable: URL(fileURLWithPath: "/apps/PiBoard.app/Contents/Resources/node/bin/node"),
        npmCLI: URL(fileURLWithPath: "/apps/PiBoard.app/Contents/Resources/node/lib/npm-cli.js")
    )
    private let entry = URL(fileURLWithPath: "/support/runtime/pi/versions/1.0.4/dist/bundle/cli.js")

    private func run(_ result: CommandResult?, record: CallRecorder? = nil) -> PiExtensionUpdateOutcome {
        PiExtensionUpdater.run(
            runner: StubRunner { arguments, environment in
                record?.record(arguments: arguments, environment: environment)
                return result
            },
            node: node,
            entry: entry
        )
    }

    @Test func updatesPackagesOnlyAndNeverTheRuntime() {
        let recorder = CallRecorder()
        _ = run(CommandResult(exitCode: 0, stdout: "", stderr: "", timedOut: false), record: recorder)
        #expect(recorder.arguments == [entry.path, "update", "--extensions"])
    }

    // CI and a dumb terminal keep Pi from drawing its TUI or waiting on a prompt.
    @Test func runsNonInteractively() {
        let recorder = CallRecorder()
        _ = run(CommandResult(exitCode: 0, stdout: "", stderr: "", timedOut: false), record: recorder)
        #expect(recorder.environment["CI"] == "1")
        #expect(recorder.environment["TERM"] == "dumb")
    }

    @Test func successKeepsTheOutput() {
        let outcome = run(CommandResult(exitCode: 0, stdout: "updated 2 packages", stderr: "", timedOut: false))
        #expect(outcome.outcome == .success)
        #expect(outcome.log == "updated 2 packages")
    }

    @Test func nonZeroExitIsReportedWithItsStatus() {
        let outcome = run(CommandResult(exitCode: 3, stdout: "", stderr: "network unreachable", timedOut: false))
        #expect(outcome.outcome == .failure("Pi exited with status 3"))
        #expect(outcome.log == "network unreachable")
    }

    @Test func timeoutIsReportedSeparatelyFromAFailingExit() {
        let outcome = run(CommandResult(exitCode: 0, stdout: "cloning...", stderr: "", timedOut: true))
        #expect(outcome.outcome == .failure("Updating extensions timed out"))
    }

    @Test func aProcessThatNeverStartsIsReported() {
        #expect(run(nil).outcome == .failure("Could not launch Pi to update extensions"))
    }
}

private struct StubRunner: CommandRunning {
    let handler: @Sendable ([String], [String: String]) -> CommandResult?

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?,
        cancellation: CommandCancellation?
    ) -> CommandResult? {
        handler(arguments, environment)
    }
}

private final class CallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedArguments: [String] = []
    private var recordedEnvironment: [String: String] = [:]

    var arguments: [String] { lock.withLock { recordedArguments } }
    var environment: [String: String] { lock.withLock { recordedEnvironment } }

    func record(arguments: [String], environment: [String: String]) {
        lock.withLock {
            recordedArguments = arguments
            recordedEnvironment = environment
        }
    }
}
