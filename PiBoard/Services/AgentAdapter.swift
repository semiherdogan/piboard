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

    var sessionID: String {
        switch self {
        case .newSession(let sessionID, _, _), .resume(let sessionID): sessionID
        }
    }
}

/// Where the Working and Idle signal comes from for this agent.
enum AgentActivitySource: Equatable, Sendable {
    /// OSC 9;4 progress sequences scanned off the pty bytes (Pi).
    case ptyProgress
    /// Events from the agent's own server, fed into the manager by an event stream (OpenCode).
    case serverEvents
    /// Working and idle from the terminal title glyph scanned off the pty; needs-input from hook
    /// events the agent posts to PiBoard (Claude Code).
    case ptyTitleWithHooks
    /// The agent gives no signal; the badge shows Running and the dots stay off.
    case unavailable
}

enum AgentAdapterError: Error, Equatable, LocalizedError {
    case invalidSessionID(String)
    case runtimeNotReady
    /// The agent's server could not be reached or refused the request; `detail` is user-facing.
    case serviceUnavailable(detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidSessionID(let id):
            "The session id \(id) is not valid for this agent."
        case .runtimeNotReady:
            "The agent runtime is not installed."
        case .serviceUnavailable(let detail):
            detail
        }
    }
}

/// Everything PiBoard needs from a coding agent. One adapter per `AgentKind`, resolved through
/// `AgentRegistry`. The process, pty, lock and runtime-state bookkeeping stay in the manager.
protocol AgentAdapter: Sendable {
    var kind: AgentKind { get }
    var activitySource: AgentActivitySource { get }
    /// Makes the id that is written to SQLite before the process exists. No I/O.
    func makeSessionID() -> String
    /// Materialises the session on the agent's side when it needs one before launch (OpenCode); a no-op for Pi.
    func prepareSession(id: String, title: String, cwd: URL) async throws
    /// Builds the launch for a session; throws when the runtime is missing or the id is not one this agent produced.
    @MainActor func launchCommand(mode: AgentLaunchMode, cwd: URL) throws -> (command: AgentLaunchCommand, runtimeVersion: String)
    /// Nil means unknown, so the launch goes ahead and the tool decides.
    func sessionExists(id: String, cwd: URL) async -> Bool?
    /// User-facing description of what a deletion removes; nil when there is nothing to remove.
    func plannedSessionRemoval(id: String, cwd: URL) -> String?
    func deleteSession(id: String, cwd: URL) async throws
    func readSessionSummary(id: String, cwd: URL) async -> SessionSummary?
}
