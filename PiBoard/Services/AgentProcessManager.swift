import Darwin
import Foundation
import Observation

/// Shared by `AgentProcessManager.stopAll` and `ShellSessions.stopAll`, which the quit path runs back to back.
enum ProcessQuitPolicy {
    /// How long graceful shutdown (observed via session state) may take before survivors are force-killed.
    static let gracePeriod: TimeInterval = 2.0
    static let pollInterval: TimeInterval = 0.05
}

/// Owns one PTY session per task and enforces the single-active-session-per-current-tree rule.
/// `runtimeStates` is the task-level view of process lifecycle; it lives here (not on
/// `BoardModel`) because it is derived from process observation, not workflow state.
@MainActor
@Observable
final class AgentProcessManager {
    enum LaunchError: Error, LocalizedError {
        case runtimeNotReady(AgentKind)
        case currentTreeBusy(ownerTaskID: UUID, kind: AgentKind)
        case projectPathMissing(URL)
        case worktreeMissing(URL)
        case nodeMissing(String)
        case sessionNotFound(String, kind: AgentKind)
        case invalidSessionID(String)
        case conversationUnsupported(AgentKind)
        /// Carries the interface that already holds the task's live session.
        case otherInterfaceActive(SessionInterface)

        var errorDescription: String? {
            switch self {
            case .runtimeNotReady(let kind):
                "The \(kind.title) runtime is not installed. Install it from Settings."
            case .currentTreeBusy(_, let kind):
                AgentStrings.currentTreeBusy(kind)
            case .projectPathMissing(let url):
                "Project folder not found at \(url.path)."
            case .worktreeMissing(let url):
                "Worktree not found at \(url.path)."
            case .nodeMissing(let detail):
                "Bundled Node runtime not found: \(detail)"
            case .sessionNotFound(_, let kind):
                AgentStrings.sessionNotFoundOnDisk(kind)
            case .invalidSessionID(let id):
                "The session id \(id) is not valid for this task's agent."
            case .conversationUnsupported(let kind):
                "\(kind.title) has no chat interface in PiBoard yet."
            case .otherInterfaceActive(let interface):
                switch interface {
                case .terminal: "This task is already running in the terminal."
                case .chat: "This task is already running in chat."
                }
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
    /// Native chat sessions; a task holds an entry here or in `sessions`, never both.
    private(set) var conversations: [UUID: ConversationSession] = [:]
    private(set) var currentTreeOwners: [String: UUID] = [:]
    var runtimeStates: [UUID: TaskRuntimeState] = [:]
    /// Pi version each task's session was launched with; internal so tests can seed it.
    var runtimeVersions: [UUID: String] = [:]
    /// Internal so tests can seed it without launching.
    var activitySources: [UUID: AgentActivitySource] = [:]
    private var externalActivities: [UUID: AgentActivity] = [:]

    /// Internal (not private) so tests can drive the lock directly without a running process.
    var lock = CurrentTreeLock()

    /// Injected so every new session picks up the terminal preferences current at launch time.
    private let makeSession: @MainActor () -> PTYSession
    private let makeConversation: @MainActor (AgentLaunchCommand) -> ConversationSession
    private let agents: AgentRegistry
    private let liveProcesses: LiveProcessRegistry?

    /// Set by the composition root once it is fully built; receives the task whose agent just
    /// finished a stretch of work.
    @ObservationIgnored var onAgentSettled: @MainActor (UUID) -> Void = { _ in }

    /// Tell an event stream which session a server-event task runs and when it is gone.
    @ObservationIgnored var onExternalSessionStarted: @MainActor (_ sessionID: String, _ taskID: UUID, _ source: AgentActivitySource) -> Void = { _, _, _ in }
    @ObservationIgnored var onExternalSessionEnded: @MainActor (_ taskID: UUID, _ source: AgentActivitySource) -> Void = { _, _ in }

    static let makeDefaultConversation: @MainActor (AgentLaunchCommand) -> ConversationSession = { command in
        ConversationSession(driver: PiRPCDriver(command: command))
    }

    init(
        makeSession: @escaping @MainActor () -> PTYSession = { PTYSession() },
        makeConversation: @escaping @MainActor (AgentLaunchCommand) -> ConversationSession = AgentProcessManager.makeDefaultConversation,
        agents: AgentRegistry,
        liveProcesses: LiveProcessRegistry? = nil
    ) {
        self.makeSession = makeSession
        self.makeConversation = makeConversation
        self.agents = agents
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
        sessionID: String,
        sharesCurrentTree: Bool = false
    ) throws -> PTYSession {
        try launch(
            task: task,
            project: project,
            runContext: runContext,
            cwd: cwd,
            mode: .newSession(sessionID: sessionID, name: task.title, initialPrompt: prompt.isEmpty ? nil : prompt),
            sharesCurrentTree: sharesCurrentTree
        )
    }

    func resume(
        task: BoardTask,
        project: Project,
        runContext: RunContext,
        cwd: URL,
        sessionID: String,
        sharesCurrentTree: Bool = false
    ) throws -> PTYSession {
        try launch(
            task: task,
            project: project,
            runContext: runContext,
            cwd: cwd,
            mode: .resume(sessionID: sessionID),
            sharesCurrentTree: sharesCurrentTree
        )
    }

    func startConversation(
        task: BoardTask,
        project: Project,
        runContext: RunContext,
        cwd: URL,
        prompt: String,
        sessionID: String,
        sharesCurrentTree: Bool = false
    ) throws -> ConversationSession {
        try launchConversation(
            task: task,
            project: project,
            runContext: runContext,
            cwd: cwd,
            mode: .newSession(sessionID: sessionID, name: task.title, initialPrompt: prompt.isEmpty ? nil : prompt),
            sharesCurrentTree: sharesCurrentTree
        )
    }

    func resumeConversation(
        task: BoardTask,
        project: Project,
        runContext: RunContext,
        cwd: URL,
        sessionID: String,
        sharesCurrentTree: Bool = false
    ) throws -> ConversationSession {
        try launchConversation(
            task: task,
            project: project,
            runContext: runContext,
            cwd: cwd,
            mode: .resume(sessionID: sessionID),
            sharesCurrentTree: sharesCurrentTree
        )
    }

    func session(for taskID: UUID) -> PTYSession? {
        sessions[taskID]
    }

    func conversation(for taskID: UUID) -> ConversationSession? {
        conversations[taskID]
    }

    /// What a running agent is doing; nil when no agent process is running for the task or the agent gives no signal.
    func agentActivity(for taskID: UUID) -> AgentActivity? {
        guard runtimeStates[taskID] == .running, let source = activitySources[taskID] else { return nil }
        switch source {
        case .ptyProgress:
            return sessions[taskID]?.agentActivity
        case .serverEvents:
            return externalActivities[taskID]
        case .ptyTitleWithHooks:
            return externalActivities[taskID] == .needsInput ? .needsInput : sessions[taskID]?.agentActivity
        case .rpcEvents:
            return conversations[taskID]?.agentActivity
        case .unavailable:
            return nil
        }
    }

    func externalActivity(for taskID: UUID) -> AgentActivity? {
        externalActivities[taskID]
    }

    /// Fed by an event stream for agents whose signal does not travel through the pty.
    func setExternalActivity(_ activity: AgentActivity?, for taskID: UUID) {
        externalActivities[taskID] = activity
    }

    func stop(taskID: UUID) {
        if let session = sessions[taskID] {
            runtimeStates[taskID] = .stopping
            session.terminate()
        } else if let conversation = conversations[taskID] {
            runtimeStates[taskID] = .stopping
            conversation.stop()
        }
    }

    static let stillRunningMessage = "The running session did not stop."

    /// Stops the task's session, force-kills a survivor after the grace period, and reports whether it is inactive.
    func stopAndWait(taskID: UUID, gracePeriod: TimeInterval = ProcessQuitPolicy.gracePeriod) async -> Bool {
        guard runtimeState(for: taskID).isActive else { return true }
        stop(taskID: taskID)
        if await waitUntilInactive(taskID: taskID, gracePeriod: gracePeriod) { return true }
        forceKill(taskID: taskID)
        return await waitUntilInactive(taskID: taskID, gracePeriod: gracePeriod)
    }

    private func waitUntilInactive(taskID: UUID, gracePeriod: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(gracePeriod)
        while runtimeState(for: taskID).isActive, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(Int(ProcessQuitPolicy.pollInterval * 1000)))
        }
        return !runtimeState(for: taskID).isActive
    }

    /// Ctrl-C for the running agent: interrupts the current turn without ending the session.
    func interrupt(taskID: UUID) {
        guard runtimeStates[taskID] == .running else { return }
        sessions[taskID]?.interrupt()
        conversations[taskID]?.interrupt()
    }

    /// Stops the given tasks' sessions and drops every trace of them, for a delete that is about
    /// to remove the tasks themselves. Asynchronous on purpose: unlike the quit path this runs
    /// while the window is up, so it must not block the main thread.
    func stopAndForget(taskIDs: [UUID]) async {
        let running = taskIDs.filter { sessions[$0] != nil || conversations[$0] != nil }
        for taskID in running {
            stop(taskID: taskID)
        }

        let deadline = Date().addingTimeInterval(ProcessQuitPolicy.gracePeriod)
        while Date() < deadline, running.contains(where: isProcessRunning) {
            try? await Task.sleep(for: .milliseconds(Int(ProcessQuitPolicy.pollInterval * 1000)))
        }
        for taskID in running where isProcessRunning(taskID) {
            forceKill(taskID: taskID)
        }

        for taskID in taskIDs {
            forget(taskID: taskID)
        }
    }

    /// Removes a task from every map keyed by task id and releases the working-tree lock it held.
    /// Without this a deleted task keeps a runtime version pinned as "in use" and can leave a tree
    /// locked by an owner that no longer exists.
    func forget(taskID: UUID) {
        endExternalSessionIfNeeded(taskID: taskID)
        sessions.removeValue(forKey: taskID)
        conversations.removeValue(forKey: taskID)
        runtimeStates.removeValue(forKey: taskID)
        runtimeVersions.removeValue(forKey: taskID)
        activitySources.removeValue(forKey: taskID)
        externalActivities.removeValue(forKey: taskID)
        for (path, owner) in currentTreeOwners where owner == taskID {
            lock.release(path: path)
            currentTreeOwners.removeValue(forKey: path)
        }
    }

    /// Blocks the caller (the app-quit path) for up to `ProcessQuitPolicy.gracePeriod` while sessions exit
    /// gracefully, then force-kills anything still running. Kept synchronous because
    /// `applicationShouldTerminate` needs a definitive answer before macOS proceeds to quit.
    func stopAll() {
        let taskIDs = Array(sessions.keys) + Array(conversations.keys)
        for taskID in taskIDs {
            stop(taskID: taskID)
        }

        let deadline = Date().addingTimeInterval(ProcessQuitPolicy.gracePeriod)
        while Date() < deadline, taskIDs.contains(where: isProcessRunning) {
            RunLoop.current.run(until: Date().addingTimeInterval(ProcessQuitPolicy.pollInterval))
        }

        for taskID in taskIDs where isProcessRunning(taskID) {
            forceKill(taskID: taskID)
        }
    }

    private func isProcessRunning(_ taskID: UUID) -> Bool {
        sessions[taskID]?.state.isRunning == true || conversations[taskID]?.runtimeState.isRunning == true
    }

    func forceKill(taskID: UUID) {
        sessions[taskID]?.forceKill()
        conversations[taskID]?.forceKill()
    }

    func applyAppearanceToAllSessions(
        _ appearance: TerminalAppearance,
        cursorStyle: TerminalCursorStyleChoice,
        optionAsMeta: Bool,
        selectsWithoutShift: Bool,
        copiesOnSelect: Bool
    ) {
        for session in sessions.values {
            session.apply(
                appearance,
                cursorStyle: cursorStyle,
                optionAsMeta: optionAsMeta,
                selectsWithoutShift: selectsWithoutShift,
                copiesOnSelect: copiesOnSelect
            )
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
        mode: AgentLaunchMode,
        sharesCurrentTree: Bool
    ) throws -> PTYSession {
        try validateWorkingDirectory(runContext: runContext, cwd: cwd)
        if isActive(conversation: task.id) { throw LaunchError.otherInterfaceActive(.chat) }
        let adapter = agents.adapter(for: task)
        let command: AgentLaunchCommand
        let runtimeVersion: String
        do {
            (command, runtimeVersion) = try adapter.launchCommand(mode: mode, cwd: cwd)
        } catch {
            throw launchError(error, kind: adapter.kind)
        }

        let lockedCWD = try acquireCurrentTreeLockIfNeeded(runContext: runContext, cwd: cwd, taskID: task.id, kind: adapter.kind, sharesCurrentTree: sharesCurrentTree)

        Diagnostics.git.info("launch task=\(task.id.uuidString, privacy: .public) context=\(runContext.rawValue, privacy: .public) cwd=\(cwd.path, privacy: .public)")
        let session = makeSession()
        session.onAgentSettled = { [weak self] in self?.agentSettled(taskID: task.id) }
        if adapter.activitySource == .ptyTitleWithHooks {
            session.activityScanner = TerminalTitleScanner()
        }
        session.onAgentActivityChanged = { [weak self] activity in
            self?.ptyActivityChanged(activity, taskID: task.id)
        }
        conversations.removeValue(forKey: task.id)
        sessions[task.id] = session
        beginRuntime(taskID: task.id, runtimeVersion: runtimeVersion, source: adapter.activitySource)
        session.start(command: command)
        if Self.usesExternalSession(adapter.activitySource) {
            onExternalSessionStarted(mode.sessionID, task.id, adapter.activitySource)
        }
        let pid = session.processID
        register(pid: pid, taskID: task.id, executablePath: command.executable.path)
        observeState(
            taskID: task.id,
            canonicalCWD: lockedCWD,
            pid: pid,
            isCurrent: { [weak self] in self?.sessions[task.id] === session },
            readState: { session.state }
        )
        return session
    }

    private func launchConversation(
        task: BoardTask,
        project: Project,
        runContext: RunContext,
        cwd: URL,
        mode: AgentLaunchMode,
        sharesCurrentTree: Bool
    ) throws -> ConversationSession {
        try validateWorkingDirectory(runContext: runContext, cwd: cwd)
        // A second conversation would orphan the live process, so it is refused like the other interface.
        if runtimeState(for: task.id).isActive {
            throw LaunchError.otherInterfaceActive(conversations[task.id] == nil ? .terminal : .chat)
        }
        let adapter = agents.adapter(for: task)
        let launch: (command: AgentLaunchCommand, runtimeVersion: String)?
        do {
            launch = try adapter.conversationLaunchCommand(mode: mode, cwd: cwd, approveProject: project.trustsPiResources)
        } catch {
            throw launchError(error, kind: adapter.kind)
        }
        guard let launch else { throw LaunchError.conversationUnsupported(adapter.kind) }

        let lockedCWD = try acquireCurrentTreeLockIfNeeded(runContext: runContext, cwd: cwd, taskID: task.id, kind: adapter.kind, sharesCurrentTree: sharesCurrentTree)

        Diagnostics.git.info("launch chat task=\(task.id.uuidString, privacy: .public) context=\(runContext.rawValue, privacy: .public) cwd=\(cwd.path, privacy: .public)")
        let session = makeConversation(launch.command)
        session.onAgentSettled = { [weak self] in self?.agentSettled(taskID: task.id) }
        session.onAgentActivityChanged = { [weak self] activity in
            self?.ptyActivityChanged(activity, taskID: task.id)
        }
        sessions.removeValue(forKey: task.id)
        conversations[task.id] = session
        // The source describes the running session, and a chat session reports through RPC events whatever the adapter's pty source is.
        beginRuntime(taskID: task.id, runtimeVersion: launch.runtimeVersion, source: .rpcEvents)
        switch mode {
        case .newSession(_, _, let initialPrompt): session.start(initialPrompt: initialPrompt)
        case .resume: session.resume()
        }
        let pid = session.processID
        register(pid: pid, taskID: task.id, executablePath: session.executablePath ?? launch.command.executable.path)
        observeState(
            taskID: task.id,
            canonicalCWD: lockedCWD,
            pid: pid,
            isCurrent: { [weak self] in self?.conversations[task.id] === session },
            readState: { session.runtimeState }
        )
        return session
    }

    private func validateWorkingDirectory(runContext: RunContext, cwd: URL) throws {
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
    }

    private func launchError(_ error: Error, kind: AgentKind) -> LaunchError {
        switch error {
        case AgentAdapterError.runtimeNotReady: .runtimeNotReady(kind)
        case AgentAdapterError.invalidSessionID(let id): .invalidSessionID(id)
        default: .nodeMissing("\(error)")
        }
    }

    private func isActive(conversation taskID: UUID) -> Bool {
        conversations[taskID] != nil && runtimeState(for: taskID).isActive
    }

    private func beginRuntime(taskID: UUID, runtimeVersion: String, source: AgentActivitySource) {
        runtimeVersions[taskID] = runtimeVersion
        activitySources[taskID] = source
        runtimeStates[taskID] = .starting
    }

    private func register(pid: pid_t?, taskID: UUID, executablePath: String) {
        guard let pid else { return }
        liveProcesses?.add(LiveProcessEntry(
            pid: pid,
            taskID: taskID,
            startedAt: ProcessInspector.startTime(pid: pid) ?? Date(),
            executablePath: executablePath
        ))
    }

    /// Returns the locked canonical path, or nil when the context does not share the project
    /// tree. Internal so tests can exercise the lock decision without spawning Pi.
    func acquireCurrentTreeLockIfNeeded(runContext: RunContext, cwd: URL, taskID: UUID, kind: AgentKind, sharesCurrentTree: Bool = false) throws -> String? {
        guard runContext == .current else { return nil }
        let canonicalCWD = Self.canonicalPath(cwd)
        // A shared session is the user's explicit choice to run two agents on the same files, so it never takes or releases the lock.
        if sharesCurrentTree, let owner = lock.owner(of: canonicalCWD), owner != taskID { return nil }
        guard lock.acquire(path: canonicalCWD, taskID: taskID) else {
            throw LaunchError.currentTreeBusy(ownerTaskID: lock.owner(of: canonicalCWD) ?? taskID, kind: kind)
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
    private func observeState(
        taskID: UUID,
        canonicalCWD: String?,
        pid: pid_t?,
        isCurrent: @escaping @MainActor () -> Bool,
        readState: @escaping @MainActor () -> PTYRuntimeState
    ) {
        withObservationTracking {
            _ = readState()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let state = readState()
                self.applyState(state, taskID: taskID, canonicalCWD: canonicalCWD, pid: pid, isCurrent: isCurrent)
                if !self.isTerminal(state) {
                    self.observeState(taskID: taskID, canonicalCWD: canonicalCWD, pid: pid, isCurrent: isCurrent, readState: readState)
                }
            }
        }
        applyState(readState(), taskID: taskID, canonicalCWD: canonicalCWD, pid: pid, isCurrent: isCurrent)
    }

    private func applyState(
        _ ptyState: PTYRuntimeState,
        taskID: UUID,
        canonicalCWD: String?,
        pid: pid_t?,
        isCurrent: @MainActor () -> Bool
    ) {
        // A forgotten or replaced session may exit late; it must not rewrite state or free a lock a newer owner holds.
        guard isCurrent() else {
            if case .exited = ptyState, let pid { liveProcesses?.remove(pid: pid) }
            return
        }
        switch ptyState {
        case .notStarted:
            break
        case .running:
            runtimeStates[taskID] = .running
        case .exited(let code):
            runtimeStates[taskID] = .exited(code)
            externalActivities.removeValue(forKey: taskID)
            endExternalSessionIfNeeded(taskID: taskID)
            releaseIfLocked(canonicalCWD)
            if let pid {
                liveProcesses?.remove(pid: pid)
            }
        }
    }

    private func endExternalSessionIfNeeded(taskID: UUID) {
        guard let source = activitySources[taskID], Self.usesExternalSession(source) else { return }
        onExternalSessionEnded(taskID, source)
    }

    private static func usesExternalSession(_ source: AgentActivitySource) -> Bool {
        switch source {
        case .serverEvents, .ptyTitleWithHooks: true
        case .ptyProgress, .rpcEvents, .unavailable: false
        }
    }

    /// Internal so tests can drive it without a pty.
    func ptyActivityChanged(_ activity: AgentActivity, taskID: UUID) {
        // The title going busy again means the user answered the prompt the hook reported.
        if activity == .working, activitySources[taskID] == .ptyTitleWithHooks { externalActivities.removeValue(forKey: taskID) }
    }

    /// Internal so tests can drive it without a pty.
    func agentSettled(taskID: UUID) {
        // Claude Code's title goes idle while a permission prompt waits, which is not the agent finishing.
        guard externalActivities[taskID] != .needsInput else { return }
        onAgentSettled(taskID)
    }

    private func isTerminal(_ state: PTYRuntimeState) -> Bool {
        if case .exited = state { return true }
        return false
    }
}
