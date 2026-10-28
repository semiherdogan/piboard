import Foundation

/// Pi: npm package run by the bundled Node, sessions as JSONL under `~/.pi/agent/sessions`, activity via OSC 9;4.
struct PiAgent: AgentAdapter {
    let kind = AgentKind.pi
    let activitySource = AgentActivitySource.ptyProgress
    private let agentDirectory: URL
    /// Read at launch so switching the active version in Settings applies to the next session only.
    private let runtime: @MainActor @Sendable () throws -> (version: String, entry: URL)
    private let locateNode: @Sendable () throws -> BundledNode

    init(
        agentDirectory: URL = PiSessionLocator.defaultAgentDirectory(),
        runtime: @escaping @MainActor @Sendable () throws -> (version: String, entry: URL),
        locateNode: @escaping @Sendable () throws -> BundledNode = { try BundledNode.locate() }
    ) {
        self.agentDirectory = agentDirectory
        self.runtime = runtime
        self.locateNode = locateNode
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
        let active: (version: String, entry: URL)
        do {
            active = try runtime()
        } catch PiRuntimeManagerError.noActiveVersion {
            throw AgentAdapterError.runtimeNotReady
        }
        let node = try locateNode()
        let command = PiLaunchCommand.build(node: node.nodeExecutable, piEntry: active.entry, mode: piMode, cwd: cwd)
        return (command.agentCommand, active.version)
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
