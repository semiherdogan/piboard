import Foundation

/// OpenCode v2: user-installed binary, sessions owned by its shared background server, activity via SSE.
struct OpenCodeAgent: AgentAdapter {
    static let sessionFlag = "--session"
    static let promptFlag = "--prompt"
    static let removalDescriptionPrefix = "OpenCode session "
    static let removalIDPrefixLength = 12
    private static let millisecondsPerSecond = 1000.0

    let kind = AgentKind.opencode
    let activitySource = AgentActivitySource.serverEvents
    private let service: OpenCodeService
    /// Read at launch so a binary found after startup applies to the next session.
    private let runtime: @MainActor @Sendable () throws -> (version: String, entry: URL)

    init(service: OpenCodeService, runtime: @escaping @MainActor @Sendable () throws -> (version: String, entry: URL)) {
        self.service = service
        self.runtime = runtime
    }

    func makeSessionID() -> String {
        OpenCodeClient.makeSessionID()
    }

    func prepareSession(id: String, title: String, cwd: URL) async throws {
        do {
            try await service.withClient { _ = try await $0.createSession(id: id, title: title, directory: cwd) }
        } catch {
            throw Self.serviceError(error)
        }
    }

    @MainActor
    func launchCommand(mode: AgentLaunchMode, cwd: URL) throws -> (command: AgentLaunchCommand, runtimeVersion: String) {
        let sessionID: String
        let initialPrompt: String?
        switch mode {
        case .newSession(let id, _, let prompt):
            sessionID = id
            initialPrompt = prompt
        case .resume(let id):
            sessionID = id
            initialPrompt = nil
        }
        guard sessionID.hasPrefix(OpenCodeClient.sessionIDPrefix) else {
            throw AgentAdapterError.invalidSessionID(sessionID)
        }
        let active: (version: String, entry: URL)
        do {
            active = try runtime()
        } catch PiRuntimeManagerError.noActiveVersion {
            throw AgentAdapterError.runtimeNotReady
        }
        // The TUI connects to the shared background service on its own, so no extra environment.
        let arguments = [Self.sessionFlag, sessionID] + (initialPrompt.map { [Self.promptFlag, $0] } ?? []) + [cwd.path]
        let command = AgentLaunchCommand(executable: active.entry, arguments: arguments, currentDirectory: cwd)
        return (command, active.version)
    }

    func sessionExists(id: String, cwd: URL) async -> Bool? {
        try? await service.withClient { try await $0.session(id: id) != nil }
    }

    func plannedSessionRemoval(id: String, cwd: URL) -> String? {
        Self.removalDescriptionPrefix + id.prefix(Self.removalIDPrefixLength)
    }

    func deleteSession(id: String, cwd: URL) async throws {
        do {
            try await service.withClient { try await $0.deleteSession(id: id) }
        } catch {
            throw Self.serviceError(error)
        }
    }

    func readSessionSummary(id: String, cwd: URL) async -> SessionSummary? {
        let loaded: (session: OpenCodeSession, text: String?)?
        do {
            loaded = try await service.withClient { client in
                guard let session = try await client.session(id: id) else { return nil }
                return (session, try await client.lastAssistantText(sessionID: id))
            }
        } catch {
            return nil
        }
        guard let (session, text) = loaded else { return nil }
        let tokens = session.tokens
        return SessionSummary(
            name: session.title,
            lastAssistantText: text,
            turnCount: 0,
            assistantMessageCount: 0,
            model: nil,
            usage: SessionSummary.Usage(
                input: tokens.input,
                output: tokens.output,
                cacheRead: tokens.cache.read,
                cacheWrite: tokens.cache.write,
                total: tokens.input + tokens.output + tokens.reasoning + tokens.cache.read + tokens.cache.write,
                cost: session.cost
            ),
            lastActivity: Date(timeIntervalSince1970: session.time.updated / Self.millisecondsPerSecond)
        )
    }

    func readSessionTranscript(id: String, cwd: URL) async -> SessionTranscript? {
        try? await service.withClient { try await $0.transcript(sessionID: id) }
    }

    private static func serviceError(_ error: Error) -> AgentAdapterError {
        .serviceUnavailable(detail: error.localizedDescription)
    }
}
