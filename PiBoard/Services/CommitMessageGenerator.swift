import Foundation

protocol CommitMessageGenerating: Sendable {
    func generate(_ context: CommitPromptContext) async throws -> String
}

enum CommitMessageGeneratorError: Error, Equatable, LocalizedError {
    case runtimeUnavailable(agent: AgentKind, reason: String)
    case failed(String)
    case timedOut(agent: AgentKind)
    case emptyResponse(agent: AgentKind)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable(let agent, let reason): "\(agent.title) is not available: \(reason)"
        case .failed(let reason): reason
        case .timedOut(let agent): "\(agent.title) did not answer in time."
        case .emptyResponse(let agent): "\(agent.title) returned an empty message."
        }
    }
}

/// Runs an agent CLI to completion off the main actor and turns its output into a commit message.
enum HeadlessCommitMessageRun {
    static func execute(
        agent: AgentKind,
        executable: URL,
        arguments: [String],
        runner: any CommandRunning,
        environment: [String: String],
        timeout: Duration
    ) async throws -> String {
        let cancellation = CommandCancellation()
        let result = await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                runner.run(
                    executable: executable,
                    arguments: arguments,
                    environment: environment,
                    timeout: timeout,
                    cancellation: cancellation
                )
            }.value
        } onCancel: {
            cancellation.cancel()
        }
        guard let result else {
            throw CommitMessageGeneratorError.runtimeUnavailable(agent: agent, reason: executable.path)
        }
        if result.cancelled || Task.isCancelled {
            throw CancellationError()
        }
        if result.timedOut {
            throw CommitMessageGeneratorError.timedOut(agent: agent)
        }
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CommitMessageGeneratorError.failed(stderr.isEmpty ? "\(agent.title) exited with code \(result.exitCode)." : stderr)
        }
        let message = CommitMessagePrompt.sanitize(result.stdout)
        guard !message.isEmpty else {
            throw CommitMessageGeneratorError.emptyResponse(agent: agent)
        }
        return message
    }
}

/// Runs Pi non-interactively with tools, extensions and context files off, so the only thing
/// it can do with the diff is describe it.
struct PiCommitMessageGenerator: CommitMessageGenerating {
    static let timeout: Duration = .seconds(90)

    /// Resolved per call so switching the active runtime or the headless options in Settings applies without a restart.
    let launch: @MainActor @Sendable () throws -> (node: URL, entry: URL)
    let options: @MainActor @Sendable () -> PiHeadlessOptions
    let runner: any CommandRunning
    let environment: [String: String]

    init(
        launch: @escaping @MainActor @Sendable () throws -> (node: URL, entry: URL),
        options: @escaping @MainActor @Sendable () -> PiHeadlessOptions = { PiHeadlessOptions() },
        runner: any CommandRunning = ProcessCommandRunner(),
        environment: [String: String] = LaunchEnvironment.shared.values
    ) {
        self.launch = launch
        self.options = options
        self.runner = runner
        self.environment = environment
    }

    func generate(_ context: CommitPromptContext) async throws -> String {
        let node: URL
        let entry: URL
        let options: PiHeadlessOptions
        do {
            (node, entry) = try await launch()
            options = await self.options()
        } catch {
            throw CommitMessageGeneratorError.runtimeUnavailable(agent: .pi, reason: error.localizedDescription)
        }
        let command = PiLaunchCommand.build(
            node: node,
            piEntry: entry,
            mode: .headless(
                prompt: CommitMessagePrompt.prompt(for: context),
                systemPrompt: CommitMessagePrompt.systemPrompt,
                model: options.model,
                extensions: options.extensions
            ),
            cwd: FileManager.default.temporaryDirectory
        )
        return try await HeadlessCommitMessageRun.execute(
            agent: .pi,
            executable: command.executable,
            arguments: command.arguments,
            runner: runner,
            environment: environment,
            timeout: Self.timeout
        )
    }
}
