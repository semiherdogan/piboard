import Foundation
import Synchronization
@testable import PiBoard

final class FakeAgentAdapter: AgentAdapter, @unchecked Sendable {
    private struct State {
        var sessionIDs: [String]
        var launches: [AgentLaunchMode] = []
        var sessionExistsCalls: [String] = []
    }

    let kind: AgentKind
    let activitySource: AgentActivitySource
    private let launchResult: Result<(AgentLaunchCommand, String), Error>
    private let sessionExistsResult: Bool?
    private let sessionFileResult: URL?
    private let summaryResult: SessionSummary?
    private let state: Mutex<State>

    init(
        kind: AgentKind = .default,
        sessionIDs: [String] = [],
        launchResult: Result<(AgentLaunchCommand, String), Error> = .failure(AgentAdapterError.runtimeNotReady),
        sessionExistsResult: Bool? = nil,
        sessionFileResult: URL? = nil,
        summaryResult: SessionSummary? = nil,
        activitySource: AgentActivitySource = .ptyProgress
    ) {
        self.kind = kind
        self.launchResult = launchResult
        self.sessionExistsResult = sessionExistsResult
        self.sessionFileResult = sessionFileResult
        self.summaryResult = summaryResult
        self.activitySource = activitySource
        state = Mutex(State(sessionIDs: sessionIDs))
    }

    var launches: [AgentLaunchMode] { state.withLock { $0.launches } }
    var sessionExistsCalls: [String] { state.withLock { $0.sessionExistsCalls } }

    func makeSessionID() -> String {
        state.withLock { $0.sessionIDs.isEmpty ? UUID().uuidString : $0.sessionIDs.removeFirst() }
    }

    @MainActor
    func launchCommand(mode: AgentLaunchMode, cwd: URL) throws -> (command: AgentLaunchCommand, runtimeVersion: String) {
        state.withLock { $0.launches.append(mode) }
        let result = try launchResult.get()
        return (result.0, result.1)
    }

    func sessionExists(id: String, cwd: URL) -> Bool? {
        state.withLock { $0.sessionExistsCalls.append(id) }
        return sessionExistsResult
    }

    func sessionFile(id: String, cwd: URL) -> URL? {
        sessionFileResult
    }

    func readSessionSummary(id: String, cwd: URL) -> SessionSummary? {
        summaryResult
    }
}

extension AgentRegistry {
    /// A Pi adapter over a sessions folder; the default runtime is never ready, so nothing launches.
    static func pi(
        agentDirectory: URL = FileManager.default.temporaryDirectory,
        runtime: @escaping @MainActor @Sendable () throws -> (version: String, entry: URL) = { throw PiRuntimeManagerError.noActiveVersion }
    ) -> AgentRegistry {
        AgentRegistry([PiAgent(agentDirectory: agentDirectory, runtime: runtime)])
    }
}
