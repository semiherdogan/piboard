import Foundation

/// User-facing phrases that name the agent. Every view goes through here so a second agent kind
/// reads "Stop OpenCode" without a change to the view.
enum AgentStrings {
    static func stop(_ kind: AgentKind) -> String { "Stop \(kind.title)" }
    static func resume(_ kind: AgentKind) -> String { "Resume \(kind.title)" }
    static func start(_ kind: AgentKind) -> String { "Start \(kind.title)" }
    static func prepareAndStart(_ kind: AgentKind) -> String { "Prepare and Start \(kind.title)..." }
    static func exited(_ kind: AgentKind, code: Int32?) -> String {
        code.map { "\(kind.title) exited (\($0))" } ?? "\(kind.title) exited"
    }
    static func notRunning(_ kind: AgentKind) -> String { "\(kind.title) is not running" }
    static func stopProcessQuestion(_ kind: AgentKind) -> String { "Stop the \(kind.title) process for this task?" }
    static func stillWorkingQuestion(_ kind: AgentKind) -> String { "\(kind.title) is still working on this task. Stop it?" }
    static func stillRunningMoveQuestion(_ kind: AgentKind) -> String {
        "\(kind.title) is still running for this task. Stop it and move?"
    }
    static func sessionNotFound(_ kind: AgentKind) -> String { "\(kind.title) session not found" }
    static func startNewSessionQuestion(_ kind: AgentKind) -> String { "Start a new \(kind.title) session?" }
    static func startNewSessionInCurrentTreeQuestion(_ kind: AgentKind) -> String {
        "Start a new \(kind.title) session in the current working tree?"
    }
    static func newSessionIDNote(_ kind: AgentKind) -> String {
        "The task gets a new \(kind.title) session ID. Its prompt, run context and worktree stay as they are."
    }
    static func runtimeNotInstalled(_ kind: AgentKind) -> String { "\(kind.title) runtime is not installed" }
    static func runtimeNotInstalledSentence(_ kind: AgentKind) -> String { "\(runtimeNotInstalled(kind))." }
    static func sessionsStillRunning(count: Int, _ kind: AgentKind) -> String { "\(count) \(kind.title) session(s)" }
    static func stopIdleHelp(_ kind: AgentKind) -> String { "Stop \(kind.title) (idle)" }
    static func alreadyRunningInTree(owner: String, _ kind: AgentKind) -> String {
        "\(owner) is already running \(kind.title) in this working tree."
    }
    static func stopBeforeRemovingWorktree(_ kind: AgentKind) -> String {
        "Stop the \(kind.title) session before removing the worktree."
    }
    static func sessionFiles(count: Int, _ kind: AgentKind) -> String {
        count == 1 ? "\(kind.title) session file" : "\(kind.title) session files"
    }
    static func sessionFilesPlural(_ kind: AgentKind) -> String { "\(kind.title) session files" }
    static func noSessionToResume(_ kind: AgentKind) -> String { "The task has no \(kind.title) session to resume." }
    static func willRunIn(path: String, _ kind: AgentKind) -> String { "\(kind.title) will run in \(path)." }
    static func currentTreeBusy(_ kind: AgentKind) -> String {
        "Another task is already running \(kind.title) in this working tree."
    }
    static func sessionNotFoundOnDisk(_ kind: AgentKind) -> String {
        "The \(kind.title) session for this task was not found on disk."
    }
}
