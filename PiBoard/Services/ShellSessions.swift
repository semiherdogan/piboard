import Foundation
import Observation

// Must match PiProcessManager's.
private let quitGracePeriod: TimeInterval = 2.0
private let quitPollInterval: TimeInterval = 0.05

/// Login shells the user opens on a project's board, one per project, independent of Pi.
/// A shell outlives the drawer that shows it; only exit, Close, project deletion or quit end it.
@MainActor
@Observable
final class ShellSessions {
    private(set) var sessions: [UUID: PTYSession] = [:]
    private let makeSession: @MainActor () -> PTYSession
    /// Injected so tests can avoid spawning the user's real login shell.
    private let start: @MainActor (PTYSession, URL) -> Void

    init(
        makeSession: @escaping @MainActor () -> PTYSession,
        start: @escaping @MainActor (PTYSession, URL) -> Void = { session, directory in
            session.startLoginShell(currentDirectory: directory.path)
        }
    ) {
        self.makeSession = makeSession
        self.start = start
    }

    func session(for projectID: UUID) -> PTYSession? {
        sessions[projectID]
    }

    var runningCount: Int {
        sessions.values.filter { $0.state.isRunning }.count
    }

    /// Returns the running shell, starting one in `directory` when there is none or the old one exited.
    @discardableResult
    func open(projectID: UUID, directory: URL) -> PTYSession {
        if let existing = sessions[projectID], existing.state.isRunning {
            return existing
        }
        let session = makeSession()
        start(session, directory)
        sessions[projectID] = session
        return session
    }

    /// SIGTERM, then forget; a shell with a foreground job still gets the pty's hangup.
    func close(projectID: UUID) {
        guard let session = sessions.removeValue(forKey: projectID) else { return }
        session.terminate()
        // An interactive shell can ignore SIGTERM; the task keeps the session alive so the kill still lands.
        Task {
            try? await Task.sleep(for: .seconds(quitGracePeriod))
            session.forceKill()
        }
    }

    /// Called when the shell exited on its own (the user typed exit): drop it so the next open starts fresh.
    func forget(projectID: UUID) {
        sessions.removeValue(forKey: projectID)
    }

    /// Same contract as `PiProcessManager.stopAll`: blocks briefly for a graceful exit, then force-kills.
    func stopAll() {
        for session in sessions.values {
            session.terminate()
        }

        let deadline = Date().addingTimeInterval(quitGracePeriod)
        while Date() < deadline, sessions.values.contains(where: { $0.state.isRunning }) {
            RunLoop.current.run(until: Date().addingTimeInterval(quitPollInterval))
        }

        for session in sessions.values where session.state.isRunning {
            session.forceKill()
        }
    }

    func applyAppearanceToAllSessions(_ appearance: TerminalAppearance, cursorStyle: TerminalCursorStyleChoice, optionAsMeta: Bool) {
        for session in sessions.values {
            session.apply(appearance, cursorStyle: cursorStyle, optionAsMeta: optionAsMeta)
        }
    }
}
