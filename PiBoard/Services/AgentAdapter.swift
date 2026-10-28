import Foundation

/// How the agent's launch is expressed: an executable plus an argument array, never a shell string.
struct AgentLaunchCommand: Equatable, Sendable {
    let executable: URL
    let arguments: [String]
    let currentDirectory: URL
}

enum AgentLaunchMode: Equatable, Sendable {
    case newSession(sessionID: String, name: String?, initialPrompt: String?)
    case resume(sessionID: String)
}

/// Where the Working and Idle signal comes from for this agent.
enum AgentActivitySource: Equatable, Sendable {
    /// OSC 9;4 progress sequences scanned off the pty bytes (Pi).
    case ptyProgress
    /// The agent gives no signal; the badge shows Running and the dots stay off.
    case unavailable
}

enum AgentAdapterError: Error, Equatable, LocalizedError {
    case invalidSessionID(String)
    case runtimeNotReady

    var errorDescription: String? {
        switch self {
        case .invalidSessionID(let id):
            "The session id \(id) is not valid for this agent."
        case .runtimeNotReady:
            "The agent runtime is not installed."
        }
    }
}

/// Everything PiBoard needs from a coding agent. One adapter per `AgentKind`, resolved through
/// `AgentRegistry`. The process, pty, lock and runtime-state bookkeeping stay in the manager.
protocol AgentAdapter: Sendable {
    var kind: AgentKind { get }
    /// Makes the id that is written to SQLite before the process exists.
    func makeSessionID() -> String
    /// Builds the launch for a session; throws when the runtime is missing or the id is not one this agent produced.
    @MainActor func launchCommand(mode: AgentLaunchMode, cwd: URL) throws -> (command: AgentLaunchCommand, runtimeVersion: String)
    /// Nil means unknown, so the launch goes ahead and the tool decides.
    func sessionExists(id: String, cwd: URL) -> Bool?
    /// The on-disk file a deletion removes; nil when the agent keeps sessions where PiBoard cannot reach them.
    func sessionFile(id: String, cwd: URL) -> URL?
    func readSessionSummary(id: String, cwd: URL) -> SessionSummary?
    var activitySource: AgentActivitySource { get }
}
