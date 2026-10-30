import Foundation

/// Runs `claude -p` with tools off and no session file, so the only thing it can do with the diff is describe it.
struct ClaudeCodeCommitMessageGenerator: CommitMessageGenerating {
    static let timeout: Duration = .seconds(90)
    static let printFlag = "-p"
    static let toolsFlag = "--tools"
    static let noTools = ""
    static let noSessionPersistenceFlag = "--no-session-persistence"
    static let outputFormatFlag = "--output-format"
    static let textOutputFormat = "text"
    static let maxTurnsFlag = "--max-turns"
    static let singleTurn = "1"
    static let systemPromptFlag = "--system-prompt"
    static let modelFlag = "--model"
    static let endOfOptions = "--"

    /// Resolved per call so a binary found after startup and a model change in Settings apply without a restart.
    let executable: @MainActor @Sendable () throws -> URL
    let model: @MainActor @Sendable () -> String?
    let runner: any CommandRunning
    let environment: [String: String]

    init(
        executable: @escaping @MainActor @Sendable () throws -> URL,
        model: @escaping @MainActor @Sendable () -> String? = { nil },
        runner: any CommandRunning = ProcessCommandRunner(),
        environment: [String: String] = LaunchEnvironment.shared.values
    ) {
        self.executable = executable
        self.model = model
        self.runner = runner
        self.environment = environment
    }

    func generate(_ context: CommitPromptContext) async throws -> String {
        let binary: URL
        let model: String?
        do {
            binary = try await executable()
            model = await self.model()
        } catch {
            throw CommitMessageGeneratorError.runtimeUnavailable(agent: .claudeCode, reason: error.localizedDescription)
        }
        let arguments = [
            Self.printFlag, Self.toolsFlag, Self.noTools,
            Self.noSessionPersistenceFlag,
            Self.outputFormatFlag, Self.textOutputFormat,
            Self.maxTurnsFlag, Self.singleTurn,
            Self.systemPromptFlag, CommitMessagePrompt.systemPrompt,
        ]
            + (model.map { [Self.modelFlag, $0] } ?? [])
            // `--tools` is variadic, so the prompt goes last after `--` to keep a leading `-` from being read as an option.
            + [Self.endOfOptions, CommitMessagePrompt.prompt(for: context)]
        return try await HeadlessCommitMessageRun.execute(
            agent: .claudeCode,
            executable: binary,
            arguments: arguments,
            runner: runner,
            environment: environment,
            timeout: Self.timeout
        )
    }
}
