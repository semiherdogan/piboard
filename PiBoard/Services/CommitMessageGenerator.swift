import Foundation

protocol CommitMessageGenerating: Sendable {
    func generate(_ context: CommitPromptContext) async throws -> String
}

enum CommitMessageGeneratorError: Error, Equatable, LocalizedError {
    case runtimeUnavailable(String)
    case failed(String)
    case timedOut
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable(let reason): "Pi is not available: \(reason)"
        case .failed(let reason): reason
        case .timedOut: "Pi did not answer in time."
        case .emptyResponse: "Pi returned an empty message."
        }
    }
}

/// Runs Pi non-interactively with tools, extensions and context files off, so the only thing
/// it can do with the diff is describe it.
struct PiCommitMessageGenerator: CommitMessageGenerating {
    static let timeout: Duration = .seconds(90)
    static let systemPrompt = """
    You write Git commit messages. Reply with the message only: no code fences, no quotes, no preamble.
    First line: imperative mood, at most 72 characters, no trailing period. \
    Add a blank line and a short body only when the diff needs explaining.
    """
    static let promptHeader = "Write a commit message for this diff."
    static let branchPrefix = "Branch: "
    static let examplesHeader = "Recent commit message examples from this repository. Match their style only when it fits the diff:"
    static let exampleBullet = "- "
    static let diffHeader = "Diff:"
    private static let codeFence = "```"
    private static let leadingMarkers: CharacterSet = ["-", "*", ">", "`", "\"", "'", " "]
    private static let trailingMarkers: CharacterSet = ["`", "\"", "'"]

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
            throw CommitMessageGeneratorError.runtimeUnavailable(error.localizedDescription)
        }
        let command = PiLaunchCommand.build(
            node: node,
            piEntry: entry,
            mode: .headless(
                prompt: Self.prompt(for: context),
                systemPrompt: Self.systemPrompt,
                model: options.model,
                extensions: options.extensions
            ),
            cwd: FileManager.default.temporaryDirectory
        )
        let runner = runner
        let environment = environment
        let cancellation = CommandCancellation()
        let result = await withTaskCancellationHandler {
            await Task.detached(priority: .userInitiated) {
                runner.run(
                    executable: command.executable,
                    arguments: command.arguments,
                    environment: environment,
                    timeout: Self.timeout,
                    cancellation: cancellation
                )
            }.value
        } onCancel: {
            cancellation.cancel()
        }
        guard let result else {
            throw CommitMessageGeneratorError.runtimeUnavailable(node.path)
        }
        if result.cancelled || Task.isCancelled {
            throw CancellationError()
        }
        if result.timedOut {
            throw CommitMessageGeneratorError.timedOut
        }
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CommitMessageGeneratorError.failed(stderr.isEmpty ? "Pi exited with code \(result.exitCode)." : stderr)
        }
        let message = Self.sanitize(result.stdout)
        guard !message.isEmpty else {
            throw CommitMessageGeneratorError.emptyResponse
        }
        return message
    }

    static func prompt(for context: CommitPromptContext) -> String {
        var sections: [String] = []
        if !context.recentSubjects.isEmpty {
            sections.append(([examplesHeader] + context.recentSubjects.map { exampleBullet + $0 }).joined(separator: "\n"))
        }
        var header = [promptHeader]
        if let branch = context.branch {
            header.append(branchPrefix + branch)
        }
        sections.append(header.joined(separator: "\n"))
        sections.append(diffHeader + "\n" + context.diff)
        return sections.joined(separator: "\n\n")
    }

    /// Strips the code fence a model sometimes adds despite the instructions, then the leading
    /// list marker or quote and trailing quote a model sometimes wraps the first line in.
    static func sanitize(_ output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(codeFence), text.hasSuffix(codeFence) {
            text.removeLast(codeFence.count)
            if let firstLineEnd = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstLineEnd)...])
            } else {
                text.removeFirst(codeFence.count)
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let firstLineEnd = text.firstIndex(of: "\n") else {
            return stripMarkers(text)
        }
        let firstLine = stripMarkers(String(text[..<firstLineEnd]))
        let rest = text[firstLineEnd...]
        return (firstLine + rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripMarkers(_ line: String) -> String {
        var line = line
        while let first = line.unicodeScalars.first, leadingMarkers.contains(first) {
            line.removeFirst()
        }
        while let last = line.unicodeScalars.last, trailingMarkers.contains(last) {
            line.removeLast()
        }
        return line
    }
}
