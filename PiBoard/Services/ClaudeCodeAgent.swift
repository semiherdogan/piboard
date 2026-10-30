import Foundation

/// Claude Code: user-installed native binary, sessions as JSONL under `~/.claude/projects`.
struct ClaudeCodeAgent: AgentAdapter {
    static let sessionIDFlag = "--session-id"
    static let nameFlag = "--name"
    static let resumeFlag = "--resume"
    static let settingsFlag = "--settings"
    static let endOfOptions = "--"

    let kind = AgentKind.claudeCode
    let activitySource = AgentActivitySource.ptyTitleWithHooks
    private let projectsDirectory: URL
    private let hooks: ClaudeCodeHooks?
    /// Read at launch so a binary found after startup applies to the next session.
    private let runtime: @MainActor @Sendable () throws -> (version: String, entry: URL)

    init(
        projectsDirectory: URL = ClaudeSessionLocator.defaultProjectsDirectory(),
        hooks: ClaudeCodeHooks? = nil,
        runtime: @escaping @MainActor @Sendable () throws -> (version: String, entry: URL)
    ) {
        self.projectsDirectory = projectsDirectory
        self.hooks = hooks
        self.runtime = runtime
    }

    func makeSessionID() -> String {
        UUID().uuidString.lowercased()
    }

    @MainActor
    func launchCommand(mode: AgentLaunchMode, cwd: URL) throws -> (command: AgentLaunchCommand, runtimeVersion: String) {
        let arguments: [String]
        switch mode {
        case .newSession(let sessionID, let name, let initialPrompt):
            try validate(sessionID)
            // The prompt stays last, after `--`, so a leading `-` is not read as an option.
            arguments = [Self.sessionIDFlag, sessionID] + (name.map { [Self.nameFlag, $0] } ?? [])
                + settingsArguments(sessionID: sessionID) + (initialPrompt.map { [Self.endOfOptions, $0] } ?? [])
        case .resume(let sessionID):
            try validate(sessionID)
            arguments = [Self.resumeFlag, sessionID] + settingsArguments(sessionID: sessionID)
        }
        let active: (version: String, entry: URL)
        do {
            active = try runtime()
        } catch PiRuntimeManagerError.noActiveVersion {
            throw AgentAdapterError.runtimeNotReady
        }
        let command = AgentLaunchCommand(executable: active.entry, arguments: arguments, currentDirectory: cwd)
        return (command, active.version)
    }

    func prepareSession(id: String, title: String, cwd: URL) async throws {
        await hooks?.start()
    }

    /// Advisory: a missing projects directory means "unknown" and Claude Code decides.
    func sessionExists(id: String, cwd: URL) async -> Bool? {
        let projectsDirectory = projectsDirectory
        return await Task.detached(priority: .utility) {
            guard ProjectPathService.exists(projectsDirectory) else { return nil }
            return ClaudeSessionLocator.sessionFile(sessionID: id, cwd: cwd, projectsDirectory: projectsDirectory) != nil
        }.value
    }

    func plannedSessionRemoval(id: String, cwd: URL) -> String? {
        sessionFile(id: id, cwd: cwd).map(ProjectPathService.abbreviated)
    }

    // Deleting under ~/.claude is approved by the owner; only files of tasks PiBoard created are removed.
    func deleteSession(id: String, cwd: URL) async throws {
        guard let file = sessionFile(id: id, cwd: cwd) else { return }
        try FileManager.default.removeItem(at: file)
    }

    func readSessionSummary(id: String, cwd: URL) async -> SessionSummary? {
        let projectsDirectory = projectsDirectory
        return await Task.detached(priority: .utility) {
            guard let file = ClaudeSessionLocator.sessionFile(sessionID: id, cwd: cwd, projectsDirectory: projectsDirectory)
            else { return nil }
            return try? ClaudeSessionReader.read(file: file)
        }.value
    }

    func readSessionTranscript(id: String, cwd: URL) async -> SessionTranscript? {
        let projectsDirectory = projectsDirectory
        return await Task.detached(priority: .utility) {
            guard let file = ClaudeSessionLocator.sessionFile(sessionID: id, cwd: cwd, projectsDirectory: projectsDirectory)
            else { return nil }
            return try? ClaudeSessionReader.transcript(file: file)
        }.value
    }

    private func sessionFile(id: String, cwd: URL) -> URL? {
        ClaudeSessionLocator.sessionFile(sessionID: id, cwd: cwd, projectsDirectory: projectsDirectory)
    }

    @MainActor
    private func settingsArguments(sessionID: String) -> [String] {
        hooks?.settingsJSON(sessionID: sessionID).map { [Self.settingsFlag, $0] } ?? []
    }

    private func validate(_ id: String) throws {
        guard UUID(uuidString: id) != nil else {
            throw AgentAdapterError.invalidSessionID(id)
        }
    }
}
