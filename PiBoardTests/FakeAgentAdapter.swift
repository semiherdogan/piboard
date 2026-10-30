import Foundation
import Synchronization
@testable import PiBoard

final class FakeAgentAdapter: AgentAdapter, @unchecked Sendable {
    private struct State {
        var sessionIDs: [String]
        var launches: [AgentLaunchMode] = []
        var sessionExistsCalls: [String] = []
        var prepared: [String] = []
        var deleted: [String] = []
    }

    let kind: AgentKind
    let activitySource: AgentActivitySource
    private let launchResult: Result<(AgentLaunchCommand, String), Error>
    private let sessionExistsResult: Bool?
    private let prepareSessionResult: Result<Void, Error>
    private let plannedRemoval: String?
    private let deleteResult: Result<Void, Error>
    private let summaryResult: SessionSummary?
    private let transcriptResult: SessionTranscript?
    private let state: Mutex<State>

    init(
        kind: AgentKind = .default,
        sessionIDs: [String] = [],
        launchResult: Result<(AgentLaunchCommand, String), Error> = .failure(AgentAdapterError.runtimeNotReady),
        sessionExistsResult: Bool? = nil,
        prepareSessionResult: Result<Void, Error> = .success(()),
        plannedRemoval: String? = nil,
        deleteResult: Result<Void, Error> = .success(()),
        summaryResult: SessionSummary? = nil,
        transcriptResult: SessionTranscript? = nil,
        activitySource: AgentActivitySource = .ptyProgress
    ) {
        self.kind = kind
        self.launchResult = launchResult
        self.sessionExistsResult = sessionExistsResult
        self.prepareSessionResult = prepareSessionResult
        self.plannedRemoval = plannedRemoval
        self.deleteResult = deleteResult
        self.summaryResult = summaryResult
        self.transcriptResult = transcriptResult
        self.activitySource = activitySource
        state = Mutex(State(sessionIDs: sessionIDs))
    }

    var launches: [AgentLaunchMode] { state.withLock { $0.launches } }
    var sessionExistsCalls: [String] { state.withLock { $0.sessionExistsCalls } }
    var prepared: [String] { state.withLock { $0.prepared } }
    var deleted: [String] { state.withLock { $0.deleted } }

    func makeSessionID() -> String {
        state.withLock { $0.sessionIDs.isEmpty ? UUID().uuidString : $0.sessionIDs.removeFirst() }
    }

    func prepareSession(id: String, title: String, cwd: URL) async throws {
        state.withLock { $0.prepared.append(id) }
        try prepareSessionResult.get()
    }

    @MainActor
    func launchCommand(mode: AgentLaunchMode, cwd: URL) throws -> (command: AgentLaunchCommand, runtimeVersion: String) {
        state.withLock { $0.launches.append(mode) }
        let result = try launchResult.get()
        return (result.0, result.1)
    }

    func sessionExists(id: String, cwd: URL) async -> Bool? {
        state.withLock { $0.sessionExistsCalls.append(id) }
        return sessionExistsResult
    }

    func plannedSessionRemoval(id: String, cwd: URL) -> String? {
        plannedRemoval
    }

    func deleteSession(id: String, cwd: URL) async throws {
        state.withLock { $0.deleted.append(id) }
        try deleteResult.get()
    }

    func readSessionSummary(id: String, cwd: URL) async -> SessionSummary? {
        summaryResult
    }

    func readSessionTranscript(id: String, cwd: URL) async -> SessionTranscript? {
        transcriptResult
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
