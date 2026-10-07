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
        case worktreeMissing(URL)
        case nodeMissing(String)
        case sessionNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .runtimeNotReady:
                "The Pi runtime is not installed. Install it from Settings."
            case .currentTreeBusy:
                "Another task is already running Pi in this working tree."
            case .projectPathMissing(let url):
                "Project folder not found at \(url.path)."
            case .worktreeMissing(let url):
                "Worktree not found at \(url.path)."
            case .nodeMissing(let detail):
                "Bundled Node runtime not found: \(detail)"
            case .sessionNotFound:
                "The Pi session for this task was not found on disk."
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
    /// Pi version each task's session was launched with; internal so tests can seed it.
    var runtimeVersions: [UUID: String] = [:]

    /// Internal (not private) so tests can drive the lock directly without a running process.
    var lock = CurrentTreeLock()

    /// Injected so every new session picks up the terminal preferences current at launch time.
    private let makeSession: @MainActor () -> PTYSession
    private let piAgentDirectory: URL
    private let liveProcesses: LiveProcessRegistry?

    /// Set by the composition root once it is fully built; receives the task whose agent just
    /// finished a stretch of work.
    @ObservationIgnored var onAgentSettled: @MainActor (UUID) -> Void = { _ in }

    init(
        makeSession: @escaping @MainActor () -> PTYSession = { PTYSession() },
        piAgentDirectory: URL = PiSessionLocator.defaultAgentDirectory(),
        liveProcesses: LiveProcessRegistry? = nil
    ) {
        self.makeSession = makeSession
        self.piAgentDirectory = piAgentDirectory
        self.liveProcesses = liveProcesses
    }

    /// Sessions whose process is starting, running or stopping; drives the quit confirmation.
    var activeSessionCount: Int {
        runtimeStates.values.filter(\.isActive).count
    }

    /// Runtime versions a starting, running or stopping session depends on; never deleted.
    var versionsInUse: Set<String> {
        Set(runtimeVersions.compactMap { taskID, version in
            runtimeState(for: taskID).isActive ? version : nil
        })
    }

    static func canonicalPath(_ url: URL) -> String {
        ProjectPathService.canonicalize(url).path
    }

    func start(
        task: BoardTask,
        project: Project,
        runContext: RunContext,
        cwd: URL,
        prompt: String,
        sessionID: UUID,
        runtime: PiRuntimeManager
    ) throws -> PTYSession {
        try launch(
            task: task,
            project: project,
            runContext: runContext,
            cwd: cwd,
            mode: .newSession(sessionID: sessionID, name: task.title, initialPrompt: prompt.isEmpty ? nil : prompt),
            runtime: runtime
        )
    }

    func resume(
        task: BoardTask,
        project: Project,
        runContext: RunContext,
        cwd: URL,
        sessionID: UUID,
        runtime: PiRuntimeManager
    ) throws -> PTYSession {
        try launch(task: task, project: project, runContext: runContext, cwd: cwd, mode: .resume(sessionID: sessionID), runtime: runtime)
    }

    func session(for taskID: UUID) -> PTYSession? {
        sessions[taskID]
    }

    func stop(taskID: UUID) {
        guard let session = sessions[taskID] else { return }
        runtimeStates[taskID] = .stopping
        session.terminate()
    }

    /// Stops the given tasks' sessions and drops every trace of them, for a delete that is about
    /// to remove the tasks themselves. Asynchronous on purpose: unlike the quit path this runs
    /// while the window is up, so it must not block the main thread.
    func stopAndForget(taskIDs: [UUID]) async {
        let running = taskIDs.filter { sessions[$0] != nil }
        for taskID in running {
            stop(taskID: taskID)
        }

        let deadline = Date().addingTimeInterval(quitGracePeriod)
        while Date() < deadline, running.contains(where: { sessions[$0]?.state.isRunning == true }) {
            try? await Task.sleep(for: .milliseconds(Int(quitPollInterval * 1000)))
        }
        for taskID in running {
            if let session = sessions[taskID], session.state.isRunning {
                session.forceKill()
            }
        }

        for taskID in taskIDs {
            forget(taskID: taskID)
        }
    }

    /// Removes a task from every map keyed by task id and releases the working-tree lock it held.
    /// Without this a deleted task keeps a runtime version pinned as "in use" and can leave a tree
    /// locked by an owner that no longer exists.
    func forget(taskID: UUID) {
        sessions.removeValue(forKey: taskID)
        runtimeStates.removeValue(forKey: taskID)
        runtimeVersions.removeValue(forKey: taskID)
        for (path, owner) in currentTreeOwners where owner == taskID {
            lock.release(path: path)
            currentTreeOwners.removeValue(forKey: path)
        }
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

    func applyAppearanceToAllSessions(_ appearance: TerminalAppearance, cursorStyle: TerminalCursorStyleChoice, optionAsMeta: Bool) {
        for session in sessions.values {
            session.apply(appearance, cursorStyle: cursorStyle, optionAsMeta: optionAsMeta)
        }
    }

    func runtimeState(for taskID: UUID) -> TaskRuntimeState {
        runtimeStates[taskID] ?? .notStarted
    }

    /// True when the canonical project path is locked by an owner whose task is currently
    /// starting, running or stopping; used to block path edits for that project.
    func hasActiveCurrentTreeSession(projectPath: URL) -> Bool {
        let canonicalPath = Self.canonicalPath(projectPath)
        guard let ownerTaskID = lock.owner(of: canonicalPath) else { return false }
        switch runtimeState(for: ownerTaskID) {
        case .starting, .running, .stopping:
            return true
        case .notStarted, .exited, .failed:
            return false
        }
    }

    private func launch(
        task: BoardTask,
        project: Project,
        runContext: RunContext,
        cwd: URL,
        mode: PiLaunchCommand.Mode,
        runtime: PiRuntimeManager
    ) throws -> PTYSession {
        switch runContext {
        case .current:
            guard FileManager.default.fileExists(atPath: cwd.path) else {
                throw LaunchError.projectPathMissing(cwd)
            }
        case .worktree:
            // Never fall back to the project root: that would run Pi against the wrong tree.
            guard ProjectPathService.exists(cwd) else {
                throw LaunchError.worktreeMissing(cwd)
            }
        }
        if case .resume(let sessionID) = mode {
            try checkSessionExists(sessionID: sessionID, cwd: cwd, taskID: task.id)
        }
        guard case .ready = runtime.status else {
            throw LaunchError.runtimeNotReady
        }

        let lockedCWD = try acquireCurrentTreeLockIfNeeded(runContext: runContext, cwd: cwd, taskID: task.id)

        let node: BundledNode
        let piEntry: URL
        let runtimeVersion: String
        do {
            node = try BundledNode.locate()
            (runtimeVersion, piEntry) = try runtime.activeEntry()
        } catch {
            releaseIfLocked(lockedCWD)
            throw LaunchError.nodeMissing("\(error)")
        }

        Diagnostics.git.info("launch task=\(task.id.uuidString, privacy: .public) context=\(runContext.rawValue, privacy: .public) cwd=\(cwd.path, privacy: .public)")
        let command = PiLaunchCommand.build(node: node.nodeExecutable, piEntry: piEntry, mode: mode, cwd: cwd)
        let session = makeSession()
        let onAgentSettled = onAgentSettled
        session.onAgentSettled = { onAgentSettled(task.id) }
        sessions[task.id] = session
        runtimeVersions[task.id] = runtimeVersion
        runtimeStates[task.id] = .starting
        session.start(command: command)
        let pid = session.processID
        if let pid {
            liveProcesses?.add(LiveProcessEntry(
                pid: pid,
                taskID: task.id,
                startedAt: ProcessInspector.startTime(pid: pid) ?? Date(),
                executablePath: command.executable.path
            ))
        }
        observeState(of: session, taskID: task.id, canonicalCWD: lockedCWD, pid: pid)
        return session
    }

    /// Advisory: a custom `--session-dir` or Pi settings can store sessions elsewhere, so a
    /// missing default directory means "unknown" and Pi decides.
    private func checkSessionExists(sessionID: UUID, cwd: URL, taskID: UUID) throws {
        let directory = PiSessionLocator.sessionsDirectory(agentDir: piAgentDirectory, cwd: cwd)
        guard ProjectPathService.exists(directory) else {
            Diagnostics.process.info("session check skipped task=\(taskID.uuidString, privacy: .public) missingDirectory=\(directory.path, privacy: .public)")
            return
        }
        guard PiSessionLocator.sessionFileExists(sessionID: sessionID, cwd: cwd, agentDir: piAgentDirectory) else {
            Diagnostics.process.info("session not found task=\(taskID.uuidString, privacy: .public) session=\(sessionID.uuidString, privacy: .public)")
            throw LaunchError.sessionNotFound(sessionID)
        }
    }

    /// Returns the locked canonical path, or nil when the context does not share the project
    /// tree. Internal so tests can exercise the lock decision without spawning Pi.
    func acquireCurrentTreeLockIfNeeded(runContext: RunContext, cwd: URL, taskID: UUID) throws -> String? {
        guard runContext == .current else { return nil }
        let canonicalCWD = Self.canonicalPath(cwd)
        guard lock.acquire(path: canonicalCWD, taskID: taskID) else {
            throw LaunchError.currentTreeBusy(ownerTaskID: lock.owner(of: canonicalCWD) ?? taskID)
        }
        currentTreeOwners[canonicalCWD] = taskID
        return canonicalCWD
    }

    private func releaseIfLocked(_ path: String?) {
        guard let path else { return }
        lock.release(path: path)
        currentTreeOwners.removeValue(forKey: path)
    }

    /// Re-registers `withObservationTracking` after every change until the session exits, at
    /// which point tracking simply stops being re-armed, so nothing keeps observing a dead session.
    private func observeState(of session: PTYSession, taskID: UUID, canonicalCWD: String?, pid: pid_t?) {
        withObservationTracking {
            _ = session.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyState(session.state, taskID: taskID, canonicalCWD: canonicalCWD, pid: pid)
                if !self.isTerminal(session.state) {
                    self.observeState(of: session, taskID: taskID, canonicalCWD: canonicalCWD, pid: pid)
                }
            }
        }
        applyState(session.state, taskID: taskID, canonicalCWD: canonicalCWD, pid: pid)
    }

    private func applyState(_ ptyState: PTYRuntimeState, taskID: UUID, canonicalCWD: String?, pid: pid_t?) {
        switch ptyState {
        case .notStarted:
            break
        case .running:
            runtimeStates[taskID] = .running
        case .exited(let code):
            runtimeStates[taskID] = .exited(code)
            releaseIfLocked(canonicalCWD)
            if let pid {
                liveProcesses?.remove(pid: pid)
            }
        }
    }

    private func isTerminal(_ state: PTYRuntimeState) -> Bool {
        if case .exited = state { return true }
        return false
    }
}
