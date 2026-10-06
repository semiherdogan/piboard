import Darwin
import Foundation
import Observation

/// How long `stopAll()` waits for graceful shutdown (observed via `runtimeStates`) before
/// force-killing any sessions still running, used on the app-quit path only.
private let quitGracePeriod: TimeInterval = 2.0
private let quitPollInterval: TimeInterval = 0.05

/// Owns one PTY session per task and enforces the single-active-session-per-current-tree rule.
/// `runtimeStates` is the task-level view of process lifecycle; it lives here (not on
/// `BoardModel`) because it is derived from process observation, not workflow state.
@MainActor
@Observable
final class PiProcessManager {
    enum LaunchError: Error, LocalizedError {
        case runtimeNotReady
        case currentTreeBusy(ownerTaskID: UUID)
        case projectPathMissing(URL)
        case nodeMissing(String)

        var errorDescription: String? {
            switch self {
            case .runtimeNotReady:
                "The Pi runtime is not installed. Install it from Settings."
            case .currentTreeBusy:
                "Another task is already running Pi in this working tree."
            case .projectPathMissing(let url):
                "Project folder not found at \(url.path)."
            case .nodeMissing(let detail):
                "Bundled Node runtime not found: \(detail)"
            }
        }
    }

    /// Enforces at most one owner per canonical working-tree path. Pure and side-effect-free
    /// so it can be unit tested without a running process.
    struct CurrentTreeLock {
        private var owners: [String: UUID] = [:]

        mutating func acquire(path: String, taskID: UUID) -> Bool {
            if let existing = owners[path], existing != taskID {
                return false
            }
            owners[path] = taskID
            return true
        }

        mutating func release(path: String) {
            owners.removeValue(forKey: path)
        }

        func owner(of path: String) -> UUID? {
            owners[path]
        }
    }

    private(set) var sessions: [UUID: PTYSession] = [:]
    private(set) var currentTreeOwners: [String: UUID] = [:]
    var runtimeStates: [UUID: TaskRuntimeState] = [:]

    private var lock = CurrentTreeLock()

    static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    func start(
        task: BoardTask,
        project: Project,
        runContext: RunContext,
        prompt: String,
        sessionID: UUID,
        runtime: PiRuntimeManager
    ) throws -> PTYSession {
        try launch(
            task: task,
            project: project,
            runContext: runContext,
            mode: .newSession(sessionID: sessionID, name: task.title, initialPrompt: prompt.isEmpty ? nil : prompt),
            runtime: runtime
        )
    }

    func resume(
        task: BoardTask,
        project: Project,
        runContext: RunContext,
        sessionID: UUID,
        runtime: PiRuntimeManager
    ) throws -> PTYSession {
        try launch(task: task, project: project, runContext: runContext, mode: .resume(sessionID: sessionID), runtime: runtime)
    }

    func session(for taskID: UUID) -> PTYSession? {
        sessions[taskID]
    }

    func stop(taskID: UUID) {
        guard let session = sessions[taskID] else { return }
        runtimeStates[taskID] = .stopping
        session.terminate()
    }

    /// Blocks the caller (the app-quit path) for up to `quitGracePeriod` while sessions exit
    /// gracefully, then force-kills anything still running. Kept synchronous because
    /// `applicationShouldTerminate` needs a definitive answer before macOS proceeds to quit.
    func stopAll() {
        for taskID in sessions.keys {
            stop(taskID: taskID)
        }

        let deadline = Date().addingTimeInterval(quitGracePeriod)
        while Date() < deadline, sessions.values.contains(where: { $0.state.isRunning }) {
            RunLoop.current.run(until: Date().addingTimeInterval(quitPollInterval))
        }

        for session in sessions.values where session.state.isRunning {
            session.forceKill()
        }
    }

    func runtimeState(for taskID: UUID) -> TaskRuntimeState {
        runtimeStates[taskID] ?? .notStarted
    }

    private func launch(
        task: BoardTask,
        project: Project,
        runContext: RunContext,
        mode: PiLaunchCommand.Mode,
        runtime: PiRuntimeManager
    ) throws -> PTYSession {
        guard FileManager.default.fileExists(atPath: project.path.path) else {
            throw LaunchError.projectPathMissing(project.path)
        }
        guard case .ready = runtime.status else {
            throw LaunchError.runtimeNotReady
        }

        let canonicalCWD = Self.canonicalPath(project.path)
        var lockedCWD: String?
        if runContext == .current {
            guard lock.acquire(path: canonicalCWD, taskID: task.id) else {
                throw LaunchError.currentTreeBusy(ownerTaskID: lock.owner(of: canonicalCWD) ?? task.id)
            }
            currentTreeOwners[canonicalCWD] = task.id
            lockedCWD = canonicalCWD
        }

        let node: BundledNode
        let piEntry: URL
        do {
            node = try BundledNode.locate()
            piEntry = try runtime.activeEntry()
        } catch {
            releaseIfLocked(lockedCWD)
            throw LaunchError.nodeMissing("\(error)")
        }

        let command = PiLaunchCommand.build(node: node.nodeExecutable, piEntry: piEntry, mode: mode, cwd: project.path)
        let session = PTYSession()
        sessions[task.id] = session
        runtimeStates[task.id] = .starting
        session.start(command: command)
        observeState(of: session, taskID: task.id, canonicalCWD: lockedCWD)
        return session
    }

    private func releaseIfLocked(_ path: String?) {
        guard let path else { return }
        lock.release(path: path)
        currentTreeOwners.removeValue(forKey: path)
    }

    /// Re-registers `withObservationTracking` after every change until the session exits, at
    /// which point tracking simply stops being re-armed, so nothing keeps observing a dead session.
    private func observeState(of session: PTYSession, taskID: UUID, canonicalCWD: String?) {
        withObservationTracking {
            _ = session.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyState(session.state, taskID: taskID, canonicalCWD: canonicalCWD)
                if !self.isTerminal(session.state) {
                    self.observeState(of: session, taskID: taskID, canonicalCWD: canonicalCWD)
                }
            }
        }
        applyState(session.state, taskID: taskID, canonicalCWD: canonicalCWD)
    }

    private func applyState(_ ptyState: PTYRuntimeState, taskID: UUID, canonicalCWD: String?) {
        switch ptyState {
        case .notStarted:
            break
        case .running:
            runtimeStates[taskID] = .running
        case .exited(let code):
            runtimeStates[taskID] = .exited(code)
            releaseIfLocked(canonicalCWD)
        }
    }

    private func isTerminal(_ state: PTYRuntimeState) -> Bool {
        if case .exited = state { return true }
        return false
    }
}
