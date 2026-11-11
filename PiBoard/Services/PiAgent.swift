import Foundation

/// Pi (npm package under the bundled Node): keeps sessions as JSONL under ~/.pi/agent/sessions and
/// reports activity via OSC 9;4.
struct PiAgent: AgentAdapter {
    let kind: AgentKind
    let activitySource = AgentActivitySource.ptyProgress
    let supportsConversation = true
    private let agentDirectory: URL
    /// Read at launch so switching the active version in Settings applies to the next session only.
    private let launch: @MainActor @Sendable () throws -> (version: String, launcher: PiLauncher)

    init(
        kind: AgentKind = .pi,
        agentDirectory: URL = PiSessionLocator.defaultAgentDirectory(),
        launch: @escaping @MainActor @Sendable () throws -> (version: String, launcher: PiLauncher)
    ) {
        self.kind = kind
        self.agentDirectory = agentDirectory
        self.launch = launch
    }

    init(
        agentDirectory: URL = PiSessionLocator.defaultAgentDirectory(),
        runtime: @escaping @MainActor @Sendable () throws -> (version: String, entry: URL),
        locateNode: @escaping @Sendable () throws -> BundledNode = { try BundledNode.locate() }
    ) {
        self.init(kind: .pi, agentDirectory: agentDirectory, launch: {
            let active = try runtime()
            return PiEngineLaunch.pi(active: active, node: try locateNode())
        })
    }

    func makeSessionID() -> String {
        UUID().uuidString
    }

    @MainActor
    func launchCommand(mode: AgentLaunchMode, cwd: URL) throws -> (command: AgentLaunchCommand, runtimeVersion: String) {
        let piMode: PiLaunchCommand.Mode
        switch mode {
        case .newSession(let sessionID, let name, let initialPrompt):
            piMode = .newSession(sessionID: try parse(sessionID), name: name, initialPrompt: initialPrompt)
        case .resume(let sessionID):
            piMode = .resume(sessionID: try parse(sessionID))
        }
        let resolved: (version: String, launcher: PiLauncher)
        do {
            resolved = try launch()
        } catch PiRuntimeManagerError.noActiveVersion {
            throw AgentAdapterError.runtimeNotReady
        }
        let command = PiLaunchCommand.build(launcher: resolved.launcher, mode: piMode, cwd: cwd)
        return (command.agentCommand, resolved.version)
    }

    @MainActor
    func conversationLaunchCommand(
        mode: AgentLaunchMode,
        cwd: URL,
        approveProject: Bool
    ) throws -> (command: AgentLaunchCommand, runtimeVersion: String)? {
        let piMode: PiLaunchCommand.Mode
        switch mode {
        case .newSession(let sessionID, let name, _):
            piMode = .rpcNewSession(sessionID: try parse(sessionID), name: name, approveProject: approveProject)
        case .resume(let sessionID):
            piMode = .rpcResume(sessionID: try parse(sessionID), approveProject: approveProject)
        }
        let resolved: (version: String, launcher: PiLauncher)
        do {
            resolved = try launch()
        } catch PiRuntimeManagerError.noActiveVersion {
            throw AgentAdapterError.runtimeNotReady
        }
        let command = PiLaunchCommand.build(launcher: resolved.launcher, mode: piMode, cwd: cwd)
        return (command.agentCommand, resolved.version)
    }

    func prepareSession(id: String, title: String, cwd: URL) async throws {}

    /// Advisory: a custom `--session-dir` or Pi settings can store sessions elsewhere, so a
    /// missing default directory means "unknown" and Pi decides.
    func sessionExists(id: String, cwd: URL) async -> Bool? {
        let agentDirectory = agentDirectory
        return await Task.detached(priority: .utility) {
            guard let sessionID = UUID(uuidString: id) else { return nil }
            let directory = PiSessionLocator.sessionsDirectory(agentDir: agentDirectory, cwd: cwd)
            guard ProjectPathService.exists(directory) else { return nil }
            return PiSessionLocator.sessionFileExists(sessionID: sessionID, cwd: cwd, agentDir: agentDirectory)
        }.value
    }

    func plannedSessionRemoval(id: String, cwd: URL) -> String? {
        sessionFile(id: id, cwd: cwd).map(ProjectPathService.abbreviated)
    }

    func deleteSession(id: String, cwd: URL) async throws {
        guard let file = sessionFile(id: id, cwd: cwd) else { return }
        try FileManager.default.removeItem(at: file)
    }

    func readSessionSummary(id: String, cwd: URL) async -> SessionSummary? {
        let agentDirectory = agentDirectory
        return await Task.detached(priority: .utility) {
            guard let sessionID = UUID(uuidString: id),
                  let file = PiSessionLocator.sessionFile(sessionID: sessionID, cwd: cwd, agentDir: agentDirectory)
            else { return nil }
            return try? PiSessionReader.read(file: file)
        }.value
    }

    func readSessionTranscript(id: String, cwd: URL) async -> SessionTranscript? {
        let agentDirectory = agentDirectory
        return await Task.detached(priority: .utility) {
            guard let sessionID = UUID(uuidString: id),
                  let file = PiSessionLocator.sessionFile(sessionID: sessionID, cwd: cwd, agentDir: agentDirectory)
            else { return nil }
            return try? PiSessionReader.transcript(file: file)
        }.value
    }

    private func sessionFile(id: String, cwd: URL) -> URL? {
        guard let sessionID = UUID(uuidString: id) else { return nil }
        return PiSessionLocator.sessionFile(sessionID: sessionID, cwd: cwd, agentDir: agentDirectory)
    }

    private func parse(_ id: String) throws -> UUID {
        guard let sessionID = UUID(uuidString: id) else {
            throw AgentAdapterError.invalidSessionID(id)
        }
        return sessionID
    }
}
