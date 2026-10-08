import Foundation
import Synchronization
import Testing
@testable import PiBoard

private struct FakeGeneratorRunner: CommandRunning, @unchecked Sendable {
    let result: CommandResult?
    let recordedArguments: RecordedArguments

    final class RecordedArguments: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [String] = []

        func set(_ arguments: [String]) { lock.withLock { value = arguments } }
        func get() -> [String] { lock.withLock { value } }
    }

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?,
        cancellation: CommandCancellation?
    ) -> CommandResult? {
        recordedArguments.set(arguments)
        return result
    }
}

private final class Flag: Sendable {
    private let storage = Mutex(false)

    func set() { storage.withLock { $0 = true } }
    func get() -> Bool { storage.withLock { $0 } }
}

private struct BlockingRunner: CommandRunning {
    static let pollInterval: TimeInterval = 0.01
    static let maxWait: TimeInterval = 2

    let terminated: Flag

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?,
        cancellation: CommandCancellation?
    ) -> CommandResult? {
        let terminated = terminated
        cancellation?.onStart { terminated.set() }
        let deadline = Date().addingTimeInterval(Self.maxWait)
        while !terminated.get(), Date() < deadline {
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
        return CommandResult(exitCode: 0, stdout: "late", stderr: "", timedOut: false, cancelled: true)
    }
}

struct CommitMessageGeneratorTests {
    private static let node = URL(fileURLWithPath: "/fake/node")
    private static let entry = URL(fileURLWithPath: "/fake/cli.js")

    private static let launch: @MainActor @Sendable () throws -> (node: URL, entry: URL) = {
        (node: node, entry: entry)
    }

    private func generator(result: CommandResult?) -> (PiCommitMessageGenerator, FakeGeneratorRunner.RecordedArguments) {
        let recorded = FakeGeneratorRunner.RecordedArguments()
        let runner = FakeGeneratorRunner(result: result, recordedArguments: recorded)
        return (PiCommitMessageGenerator(launch: Self.launch, runner: runner, environment: [:]), recorded)
    }

    private static let noSubjectsContext = CommitPromptContext(diff: "diff", branch: nil, recentSubjects: [])

    private static func context(diff: String = "diff", branch: String? = nil, recentSubjects: [String] = []) -> CommitPromptContext {
        CommitPromptContext(diff: diff, branch: branch, recentSubjects: recentSubjects)
    }

    @Test func trimsWhitespaceFromStdout() async throws {
        let (generator, _) = generator(result: .ok(stdout: " OK\n"))

        let message = try await generator.generate(Self.noSubjectsContext)

        #expect(message == "OK")
    }

    @Test func stripsACodeFenceAroundTheMessage() async throws {
        let (generator, _) = generator(result: .ok(stdout: "```\nOK\n```"))

        let message = try await generator.generate(Self.noSubjectsContext)

        #expect(message == "OK")
    }

    @Test func nilResultIsRuntimeUnavailable() async throws {
        let (generator, _) = generator(result: nil)

        await #expect(throws: CommitMessageGeneratorError.runtimeUnavailable(Self.node.path)) {
            try await generator.generate(Self.noSubjectsContext)
        }
    }

    @Test func cancellingTheTaskStopsTheProcess() async throws {
        let terminated = Flag()
        let generator = PiCommitMessageGenerator(
            launch: Self.launch,
            runner: BlockingRunner(terminated: terminated),
            environment: [:]
        )
        let task = Task { try await generator.generate(Self.noSubjectsContext) }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(terminated.get())
    }

    @Test func timedOutResultIsTimedOut() async throws {
        let (generator, _) = generator(result: CommandResult(exitCode: 0, stdout: "", stderr: "", timedOut: true))

        await #expect(throws: CommitMessageGeneratorError.timedOut) {
            try await generator.generate(Self.noSubjectsContext)
        }
    }

    @Test func nonZeroExitWithStderrIsFailed() async throws {
        let (generator, _) = generator(result: CommandResult(exitCode: 1, stdout: "", stderr: "boom", timedOut: false))

        await #expect(throws: CommitMessageGeneratorError.failed("boom")) {
            try await generator.generate(Self.noSubjectsContext)
        }
    }

    @Test func emptyStdoutIsEmptyResponse() async throws {
        let (generator, _) = generator(result: .ok(stdout: "   "))

        await #expect(throws: CommitMessageGeneratorError.emptyResponse) {
            try await generator.generate(Self.noSubjectsContext)
        }
    }

    @Test func argumentsEndWithThePromptAndDisableTools() async throws {
        let (generator, recorded) = generator(result: .ok(stdout: "OK"))

        _ = try await generator.generate(Self.context(diff: "the diff", branch: "main"))

        let arguments = recorded.get()
        #expect(arguments.contains("--no-tools"))
        let prompt = arguments.last
        #expect(prompt == arguments.last)
        #expect(prompt?.hasPrefix(PiCommitMessageGenerator.promptHeader) == true)
        #expect(prompt?.contains("Branch: main") == true)
    }

    @Test func launchThrowingIsRuntimeUnavailable() async throws {
        struct LaunchError: Error, LocalizedError {
            var errorDescription: String? { "no runtime" }
        }
        let recorded = FakeGeneratorRunner.RecordedArguments()
        let runner = FakeGeneratorRunner(result: .ok(stdout: "OK"), recordedArguments: recorded)
        let generator = PiCommitMessageGenerator(
            launch: { throw LaunchError() },
            runner: runner,
            environment: [:]
        )

        await #expect(throws: CommitMessageGeneratorError.runtimeUnavailable("no runtime")) {
            try await generator.generate(Self.noSubjectsContext)
        }
    }

    @Test func promptWithSubjectsListsThemBeforeTheHeader() throws {
        let prompt = PiCommitMessageGenerator.prompt(for: Self.context(diff: "diff", recentSubjects: ["feat: a", "fix: b"]))

        #expect(prompt.contains(PiCommitMessageGenerator.examplesHeader))
        #expect(prompt.contains("- feat: a"))
        #expect(prompt.contains("- fix: b"))
        let examplesRange = try #require(prompt.range(of: PiCommitMessageGenerator.examplesHeader))
        let headerRange = try #require(prompt.range(of: PiCommitMessageGenerator.promptHeader))
        #expect(examplesRange.lowerBound < headerRange.lowerBound)
    }

    @Test func promptWithoutSubjectsOmitsTheExamplesHeader() {
        let prompt = PiCommitMessageGenerator.prompt(for: Self.noSubjectsContext)

        #expect(!prompt.contains(PiCommitMessageGenerator.examplesHeader))
    }

    @Test func sanitizeStripsALeadingListMarker() {
        #expect(PiCommitMessageGenerator.sanitize("- feat: thing") == "feat: thing")
    }

    @Test func sanitizeStripsWrappingQuotes() {
        #expect(PiCommitMessageGenerator.sanitize("\"feat: thing\"") == "feat: thing")
    }

    @Test func sanitizeKeepsTheBodyOfAFencedMessage() {
        let output = "```\nfeat: thing\n\nSome body text.\nMore body text.\n```"

        #expect(PiCommitMessageGenerator.sanitize(output) == "feat: thing\n\nSome body text.\nMore body text.")
    }

    @Test func sanitizeKeepsABodyBullet() {
        #expect(PiCommitMessageGenerator.sanitize("feat: a\n\n- body bullet") == "feat: a\n\n- body bullet")
    }
}

private extension CommandResult {
    static func ok(stdout: String) -> CommandResult {
        CommandResult(exitCode: 0, stdout: stdout, stderr: "", timedOut: false)
    }
}
