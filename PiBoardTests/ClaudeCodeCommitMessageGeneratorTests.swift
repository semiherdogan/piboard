import Foundation
import Synchronization
import Testing
@testable import PiBoard

private final class RecordingRunner: CommandRunning, Sendable {
    private let result: CommandResult?
    private let recorded = Mutex<[String]>([])

    init(result: CommandResult?) {
        self.result = result
    }

    var arguments: [String] { recorded.withLock { $0 } }

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration?,
        cancellation: CommandCancellation?
    ) -> CommandResult? {
        recorded.withLock { $0 = arguments }
        return result
    }
}

struct ClaudeCodeCommitMessageGeneratorTests {
    private static let binary = URL(fileURLWithPath: "/fake/claude")
    private static let context = CommitPromptContext(diff: "the diff", branch: "main", recentSubjects: [])

    private static func ok(_ stdout: String) -> CommandResult {
        CommandResult(exitCode: 0, stdout: stdout, stderr: "", timedOut: false)
    }

    private func generator(
        result: CommandResult?,
        model: String? = nil
    ) -> (ClaudeCodeCommitMessageGenerator, RecordingRunner) {
        let runner = RecordingRunner(result: result)
        let binary = Self.binary
        let generator = ClaudeCodeCommitMessageGenerator(
            executable: { binary },
            model: { model },
            runner: runner,
            environment: [:]
        )
        return (generator, runner)
    }

    @Test func argumentsDisableToolsAndSessionsAndSetTheSystemPrompt() async throws {
        let (generator, runner) = generator(result: Self.ok("OK"))

        _ = try await generator.generate(Self.context)

        let arguments = runner.arguments
        #expect(arguments.first == ClaudeCodeCommitMessageGenerator.printFlag)
        let toolsIndex = try #require(arguments.firstIndex(of: ClaudeCodeCommitMessageGenerator.toolsFlag))
        #expect(arguments[toolsIndex + 1] == ClaudeCodeCommitMessageGenerator.noTools)
        #expect(arguments.contains(ClaudeCodeCommitMessageGenerator.noSessionPersistenceFlag))
        let formatIndex = try #require(arguments.firstIndex(of: ClaudeCodeCommitMessageGenerator.outputFormatFlag))
        #expect(arguments[formatIndex + 1] == ClaudeCodeCommitMessageGenerator.textOutputFormat)
        let turnsIndex = try #require(arguments.firstIndex(of: ClaudeCodeCommitMessageGenerator.maxTurnsFlag))
        #expect(arguments[turnsIndex + 1] == ClaudeCodeCommitMessageGenerator.singleTurn)
        let systemIndex = try #require(arguments.firstIndex(of: ClaudeCodeCommitMessageGenerator.systemPromptFlag))
        #expect(arguments[systemIndex + 1] == CommitMessagePrompt.systemPrompt)
        #expect(!arguments.contains(ClaudeCodeCommitMessageGenerator.modelFlag))
    }

    @Test func thePromptComesLastAfterTheEndOfOptionsMarker() async throws {
        let (generator, runner) = generator(result: Self.ok("OK"))

        _ = try await generator.generate(Self.context)

        let arguments = runner.arguments
        #expect(arguments[arguments.count - 2] == ClaudeCodeCommitMessageGenerator.endOfOptions)
        #expect(arguments.last?.hasPrefix(CommitMessagePrompt.promptHeader) == true)
    }

    @Test func aModelAddsTheModelFlagBeforeTheEndOfOptionsMarker() async throws {
        let (generator, runner) = generator(result: Self.ok("OK"), model: "opus")

        _ = try await generator.generate(Self.context)

        let arguments = runner.arguments
        let modelIndex = try #require(arguments.firstIndex(of: ClaudeCodeCommitMessageGenerator.modelFlag))
        #expect(arguments[modelIndex + 1] == "opus")
        let endIndex = try #require(arguments.firstIndex(of: ClaudeCodeCommitMessageGenerator.endOfOptions))
        #expect(modelIndex < endIndex)
    }

    @Test func nilResultIsRuntimeUnavailable() async throws {
        let (generator, _) = generator(result: nil)

        await #expect(throws: CommitMessageGeneratorError.runtimeUnavailable(agent: .claudeCode, reason: Self.binary.path)) {
            try await generator.generate(Self.context)
        }
    }

    @Test func executableThrowingIsRuntimeUnavailable() async throws {
        struct MissingBinary: Error, LocalizedError {
            var errorDescription: String? { "no claude" }
        }
        let generator = ClaudeCodeCommitMessageGenerator(
            executable: { throw MissingBinary() },
            runner: RecordingRunner(result: Self.ok("OK")),
            environment: [:]
        )

        await #expect(throws: CommitMessageGeneratorError.runtimeUnavailable(agent: .claudeCode, reason: "no claude")) {
            try await generator.generate(Self.context)
        }
    }

    @Test func nonZeroExitWithStderrIsFailed() async throws {
        let (generator, _) = generator(result: CommandResult(exitCode: 1, stdout: "", stderr: "boom", timedOut: false))

        await #expect(throws: CommitMessageGeneratorError.failed("boom")) {
            try await generator.generate(Self.context)
        }
    }

    @Test func stdoutIsSanitized() async throws {
        let (generator, _) = generator(result: Self.ok("```\n- feat: thing\n```"))

        let message = try await generator.generate(Self.context)

        #expect(message == "feat: thing")
    }
}
