import AppKit
import Foundation
import Observation
import SQLite3

private let pathEnvKey = "PATH"
private let fakeExecutablePermissions = 0o755
// These two must match the strings in PiBoardUITests/FakeOpenCode.swift.
private let fakeOpenCodeNodeKey = "PIBOARD_FAKE_OPENCODE_NODE"
private let fakeOpenCodeConfigKey = "PIBOARD_FAKE_OPENCODE_CONFIG"
// These two must match the strings in PiBoardUITests/FakeClaudeCode.swift.
private let fakeClaudeNodeKey = "PIBOARD_FAKE_CLAUDE_NODE"
private let fakeClaudeHomeKey = "PIBOARD_FAKE_CLAUDE_HOME"

// Composition root for services; populated as milestones land.
@MainActor
@Observable
final class AppEnvironment {

    let piRuntime: PiRuntimeManager
    let openCodeRuntime: UserInstalledRuntime
    let claudeCodeRuntime: UserInstalledRuntime
    let claudeCodeLogin: ClaudeCodeLoginProbe
    let openCodeService: OpenCodeService
    let board: BoardModel
    let preferences: AppPreferences
    let processes: AgentProcessManager
    let openCodeEvents: OpenCodeEventStream
    let claudeCodeHooks: ClaudeCodeHooks
    let agents: AgentRegistry
    let shells: ShellSessions
    let git: GitServicing
    let gitWriter: GitWriting
    let worktrees: WorktreeServicing
    let sessionResumer: AgentSessionResumer
    let externalApps: ExternalAppActions
    let worktreeActions: WorktreeActions
    let deletions: DeletionActions
    let commits: CommitActions
    let updates: UpdateService
    let attention: TaskAttention
    let sessionSummaries: SessionSummaryStore
    let notifications: any AgentNotifying
    let shortcuts: ShortcutDispatcher
    // Set when the on-disk database was replaced after corruption, or could not be opened at
    // all (then the app runs on an in-memory database and nothing persists across launches).
    var startupError: String?
    // Pi children left running by a PiBoard run that crashed or was force-quit; shown once.
    var orphanedProcesses: [LiveProcessEntry] = []
    /// True when the user's Pi settings do not enable terminal progress, so dots and
    /// notifications would stay silent. Never set during tests, which must not read `~/.pi/agent`.
    private(set) var isTerminalProgressHintNeeded = false
    private let piSettings: PiSettingsProbe
    /// Which task's agent last went quiet, and a counter so the same task settling twice is seen.
    private(set) var lastSettledTaskID: UUID?
    private(set) var settleRevision = 0

    init(testing: TestingConfiguration = .detect()) {
        // Resolving the login shell spawns a process, so it starts now and runs while the
        // database opens, rather than blocking the first Pi launch. UI tests never spawn one.
        if !testing.isUITesting {
            LaunchEnvironment.prewarm()
        }
        let (database, startupError) = Self.openDatabase(testing: testing)
        self.startupError = startupError
        let liveProcesses = Self.makeLiveProcesses(testing: testing)
        orphanedProcesses = Self.collectOrphans(from: liveProcesses)
        piRuntime = PiRuntimeManager(paths: Self.makeRuntimePaths(testing: testing), settings: SettingsRepository(database: database))
        let (openCodeRuntime, openCodeService) = Self.makeOpenCode(testing: testing)
        self.openCodeRuntime = openCodeRuntime
        self.openCodeService = openCodeService
        claudeCodeRuntime = Self.makeClaudeCodeRuntime(testing: testing)
        claudeCodeLogin = ClaudeCodeLoginProbe()
        updates = Self.makeUpdateService(database: database, testing: testing)
        let board = Self.makeBoard(database: database, testing: testing)
        self.board = board
        attention = TaskAttention()
        // Hosted tests must not ask the user for notification permission.
        notifications = testing.isRunningTests ? NoNotifications() : AgentNotificationService()
        externalApps = ExternalAppActions(service: ExternalAppService(), board: board)
        let preferences = AppPreferences(database: database)
        self.preferences = preferences
        // The action handler needs `self`, so it is assigned once every property is initialized.
        shortcuts = ShortcutDispatcher(preferences: preferences)
        let makeSession = Self.makeSessionFactory(preferences: preferences, externalApps: externalApps)
        let agentDirectory = testing.agentDirectory ?? PiSessionLocator.defaultAgentDirectory()
        piSettings = PiSettingsProbe(agentDirectory: agentDirectory)
        claudeCodeHooks = ClaudeCodeHooks()
        let agents = AgentRegistry([
            PiAgent(agentDirectory: agentDirectory, runtime: { [piRuntime] in try piRuntime.activeEntry() }),
            OpenCodeAgent(service: openCodeService, runtime: { [openCodeRuntime] in try openCodeRuntime.activeEntry() }),
            ClaudeCodeAgent(
                projectsDirectory: Self.claudeProjectsDirectory(testing: testing),
                hooks: claudeCodeHooks,
                runtime: { [claudeCodeRuntime] in try claudeCodeRuntime.activeEntry() }
            ),
        ])
        self.agents = agents
        let sessionSummaries = SessionSummaryStore(agents: agents)
        self.sessionSummaries = sessionSummaries
        let processes = AgentProcessManager(makeSession: makeSession, agents: agents, liveProcesses: liveProcesses)
        self.processes = processes
        openCodeEvents = OpenCodeEventStream(service: openCodeService, processes: processes)
        shells = Self.makeShells(makeSession: makeSession, testing: testing)
        let git = GitService()
        let gitWriter = GitWriteService()
        let worktrees = WorktreeService(rootDirectory: Self.worktreesRoot(testing: testing))
        self.git = git
        self.gitWriter = gitWriter
        self.worktrees = worktrees
        sessionResumer = AgentSessionResumer(processes: processes, worktrees: worktrees, agents: agents)
        worktreeActions = WorktreeActions(board: board, processes: processes, git: git, worktrees: worktrees)
        deletions = DeletionActions(board: board, processes: processes, worktrees: worktrees, attention: attention, shells: shells, summaries: sessionSummaries, agents: agents)
        commits = Self.makeCommitActions(git: git, gitWriter: gitWriter, makeSession: makeSession, piRuntime: piRuntime, openCodeService: openCodeService, claudeCodeRuntime: claudeCodeRuntime, preferences: preferences)
        wireServices(testing: testing)
    }

    /// Everything that needs a fully built environment: cross-service callbacks, observers, the
    /// first runtime refresh and the background checks a test run must skip.
    private func wireServices(testing: TestingConfiguration) {
        piRuntime.versionsInUse = { [processes] in processes.versionsInUse }
        processes.onAgentSettled = { [weak self] taskID in self?.agentSettled(taskID: taskID) }
        processes.onExternalSessionStarted = { [openCodeEvents, claudeCodeHooks] sessionID, taskID, source in
            switch source {
            case .serverEvents: openCodeEvents.register(sessionID: sessionID, taskID: taskID)
            case .ptyTitleWithHooks: claudeCodeHooks.register(sessionID: sessionID, taskID: taskID)
            case .ptyProgress, .unavailable: break
            }
        }
        processes.onExternalSessionEnded = { [openCodeEvents, claudeCodeHooks] taskID, source in
            switch source {
            case .serverEvents: openCodeEvents.unregister(taskID: taskID)
            case .ptyTitleWithHooks: claudeCodeHooks.unregister(taskID: taskID)
            case .ptyProgress, .unavailable: break
            }
        }
        claudeCodeHooks.onActivity = { [processes] taskID, activity in processes.setExternalActivity(activity, for: taskID) }
        claudeCodeHooks.onNeedsInput = { [weak self] taskID in self?.agentNeedsInput(taskID: taskID) }
        openCodeEvents.onSettled = { [weak self] taskID in self?.agentSettled(taskID: taskID) }
        openCodeEvents.onNeedsInput = { [weak self] taskID in self?.agentNeedsInput(taskID: taskID) }
        shortcuts.perform = { [weak self] action in self?.perform(action) }
        observeTerminalPreferences()
        piRuntime.refresh()
        if !testing.isRunningTests || testing.fakeOpenCode != nil { openCodeRuntime.refresh() }
        if !testing.isRunningTests || testing.fakeClaudeCode != nil { claudeCodeRuntime.refresh() }
        // The listener must be up before a resume, which has no prepare step.
        if !testing.isUnitTesting, preferences.enabledAgents.contains(.claudeCode) { Task { await claudeCodeHooks.start() } }
        guard !testing.isRunningTests else { return }
        piRuntime.checkForUpdatesIfDue()
        let notifications = notifications
        Task { await notifications.requestAuthorization() }
        refreshTerminalProgressHint()
        shortcuts.start()
    }

    private nonisolated static func openDatabase(testing: TestingConfiguration) -> (Database, startupError: String?) {
        if testing.isUITesting {
            return (inMemoryDatabase(), nil)
        }
        do {
            let opened = openOrRecover(at: try AppPaths.databaseURL())
            return (opened.0, opened.recoveryNote)
        } catch {
            return (
                inMemoryDatabase(),
                "Could not locate the PiBoard database folder: \(error.localizedDescription). Changes will not be saved."
            )
        }
    }

    private static func makeLiveProcesses(testing: TestingConfiguration) -> LiveProcessRegistry? {
        // Hosted tests must never read or clear the real registry of a running PiBoard.
        guard !testing.isRunningTests else { return nil }
        return (try? LiveProcessRegistry.defaultFileURL()).map(LiveProcessRegistry.init(fileURL:))
    }

    private static func collectOrphans(from liveProcesses: LiveProcessRegistry?) -> [LiveProcessEntry] {
        guard let liveProcesses else { return [] }
        let orphans = OrphanedProcessCleanup.orphans(
            in: liveProcesses.entries,
            expectedExecutable: (try? BundledNode.locate())?.nodeExecutable
        )
        liveProcesses.clear()
        return orphans
    }

    /// The runtime behind a task's agent.
    func runtime(for kind: AgentKind) -> any AgentRuntime {
        switch kind {
        case .pi: piRuntime
        case .opencode: openCodeRuntime
        case .claudeCode: claudeCodeRuntime
        }
    }

    private static func makeClaudeCodeRuntime(testing: TestingConfiguration) -> UserInstalledRuntime {
        guard testing.isRunningTests else { return UserInstalledRuntime(package: .claudeCode) }
        // Tests must never find the real install: empty PATH and a home without ~/.local/bin/claude.
        let home = testing.uiTestingRoot ?? FileManager.default.temporaryDirectory
        let missing = UserInstalledRuntime(package: .claudeCode, environment: [pathEnvKey: ""], homeDirectory: home)
        guard let fake = testing.fakeClaudeCode, let installDirectory = testing.fakeClaudeCodeInstallDirectory,
              let root = testing.uiTestingRoot else { return missing }
        do {
            try installFakeTool(from: fake.deletingLastPathComponent(), into: installDirectory)
        } catch {
            Diagnostics.runtime.error("Could not install the fake Claude Code: \(error.localizedDescription, privacy: .public)")
            return missing
        }
        let nodePath = (try? BundledNode.locate())?.nodeExecutable.path ?? ""
        var environment = ProcessInfo.processInfo.environment
        environment[pathEnvKey] = installDirectory.path
        environment[fakeClaudeNodeKey] = nodePath
        environment[fakeClaudeHomeKey] = root.path
        // UI test only; the real app never sets them. The fake TUI child inherits them from the process.
        setenv(fakeClaudeNodeKey, nodePath, 1)
        setenv(fakeClaudeHomeKey, root.path, 1)
        return UserInstalledRuntime(package: .claudeCode, environment: environment, homeDirectory: root)
    }

    /// Tests must never read or delete under the real ~/.claude.
    private static func claudeProjectsDirectory(testing: TestingConfiguration) -> URL {
        guard testing.isRunningTests else { return ClaudeSessionLocator.defaultProjectsDirectory() }
        return ClaudeSessionLocator.defaultProjectsDirectory(home: testing.uiTestingRoot ?? FileManager.default.temporaryDirectory)
    }

    private static func makeOpenCode(testing: TestingConfiguration) -> (runtime: UserInstalledRuntime, service: OpenCodeService) {
        // Files the runner writes are quarantined and cannot be executed; a fresh copy made by the app is not.
        var installFailed = false
        let installed: URL? = testing.fakeOpenCode.flatMap { fake in
            guard let installDirectory = testing.fakeOpenCodeInstallDirectory else { return nil }
            do {
                try installFakeTool(from: fake.deletingLastPathComponent(), into: installDirectory)
                return installDirectory
            } catch {
                Diagnostics.runtime.error("Could not install the fake OpenCode: \(error.localizedDescription, privacy: .public)")
                installFailed = true
                return nil
            }
        }
        if installFailed, let home = testing.uiTestingRoot, let installDirectory = testing.fakeOpenCodeInstallDirectory {
            // A failed fake install must report OpenCode missing, never fall back to the real runtime.
            let runtime = UserInstalledRuntime(package: .opencode, environment: [pathEnvKey: installDirectory.path], homeDirectory: home)
            return (runtime, OpenCodeService(executable: { [weak runtime] in runtime?.executable }))
        }
        guard let installDirectory = installed, let configDirectory = testing.openCodeConfigDirectory,
              let home = testing.uiTestingRoot else {
            let runtime = UserInstalledRuntime(package: .opencode)
            return (runtime, OpenCodeService(executable: { [weak runtime] in runtime?.executable }))
        }
        try? FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let nodePath = (try? BundledNode.locate())?.nodeExecutable.path ?? ""
        var environment = ProcessInfo.processInfo.environment
        environment[pathEnvKey] = installDirectory.path
        environment[fakeOpenCodeNodeKey] = nodePath
        environment[fakeOpenCodeConfigKey] = configDirectory.path
        // UI test only; the real app never sets them. The fake TUI child inherits them from the process.
        setenv(fakeOpenCodeNodeKey, nodePath, 1)
        setenv(fakeOpenCodeConfigKey, configDirectory.path, 1)
        // The known install path is resolved against this home, so the real install never shadows the fake.
        let runtime = UserInstalledRuntime(package: .opencode, environment: environment, homeDirectory: home)
        let service = OpenCodeService(
            executable: { [weak runtime] in runtime?.executable },
            environment: environment,
            configDirectory: configDirectory
        )
        return (runtime, service)
    }

    private nonisolated static func makeRuntimePaths(testing: TestingConfiguration) -> AgentRuntimePaths {
        // An empty root keeps the runtime `.missing` unless the test passes a fake Pi entry.
        let paths = testing.uiTestingRoot.map { AgentRuntimePaths(package: .pi, root: $0) } ?? AgentRuntimePaths(package: .pi)
        if let entry = testing.fakePiEntry {
            do {
                try installFakeRuntime(entry: entry, into: paths)
            } catch {
                Diagnostics.runtime.error("Could not install the fake Pi runtime: \(error.localizedDescription, privacy: .public)")
            }
        }
        return paths
    }

    private static func makeUpdateService(database: Database, testing: TestingConfiguration) -> UpdateService {
        // Hosted tests must not start Sparkle, so they see the build as unconfigured.
        UpdateService(
            settings: SettingsRepository(database: database),
            publicEDKey: testing.isRunningTests ? nil : Bundle.main.object(forInfoDictionaryKey: BundleInfoKey.sparklePublicEDKey) as? String,
            makeUpdater: { SparkleUpdater(allowedChannels: $0, onStateChange: $1) }
        )
    }

    private static func makeBoard(database: Database, testing: TestingConfiguration) -> BoardModel {
        let board = BoardModel(database: database)
        if testing.isUITesting {
            SampleData.seed(into: board)
            giveProjectsRealFolders(in: board, testing: testing)
        }
        return board
    }

    private static func makeSessionFactory(preferences: AppPreferences, externalApps: ExternalAppActions) -> @MainActor () -> PTYSession {
        {
            let appearance = TerminalAppearance.make(from: preferences)
            let session = PTYSession(appearance: appearance, scrollbackLines: preferences.terminalScrollbackLines)
            session.apply(
                appearance,
                cursorStyle: preferences.terminalCursorStyle,
                optionAsMeta: preferences.terminalOptionAsMeta
            )
            // Read at click time so changing the preferred editor affects sessions already open.
            session.onOpenLink = { target in
                externalApps.open(target, editor: preferences.preferredEditor)
            }
            return session
        }
    }

    private static func makeShells(makeSession: @escaping @MainActor () -> PTYSession, testing: TestingConfiguration) -> ShellSessions {
        guard testing.isUITesting else { return ShellSessions(makeSession: makeSession) }
        let shell = uiTestingShell
        return ShellSessions(makeSession: makeSession, start: { session, directory in
            session.start(executable: shell, args: [], currentDirectory: directory.path)
        })
    }

    private nonisolated static func worktreesRoot(testing: TestingConfiguration) -> @Sendable () throws -> URL {
        guard let root = testing.worktreesRoot else { return AppPaths.worktreesDirectory }
        return { root }
    }

    private static func makeCommitActions(
        git: GitServicing,
        gitWriter: GitWriting,
        makeSession: @escaping @MainActor () -> PTYSession,
        piRuntime: PiRuntimeManager,
        openCodeService: OpenCodeService,
        claudeCodeRuntime: UserInstalledRuntime,
        preferences: AppPreferences
    ) -> CommitActions {
        CommitActions(
            changes: ChangeSetModel(git: git, writer: gitWriter),
            git: git,
            terminal: GitTerminalRunner(makeSession: makeSession),
            generator: CommitMessageGeneratorRouter(
                generators: [
                    .pi: PiCommitMessageGenerator(launch: {
                        let node = try BundledNode.locate()
                        return (node.nodeExecutable, try piRuntime.activeEntry().entry)
                    }, options: { preferences.headlessOptions }),
                    .opencode: OpenCodeCommitMessageGenerator(service: openCodeService),
                    .claudeCode: ClaudeCodeCommitMessageGenerator(
                        executable: { try claudeCodeRuntime.activeEntry().entry },
                        model: { preferences.claudeHeadlessModel }
                    ),
                ],
                selection: { preferences.commitMessageAgent }
            ),
            writer: gitWriter
        )
    }

    /// Cheap file read, done off the main actor so a slow home directory never stalls the board.
    func refreshTerminalProgressHint() {
        let probe = piSettings
        Task.detached(priority: .utility) {
            let enabled = probe.showsTerminalProgress() == true
            await MainActor.run { self.isTerminalProgressHintNeeded = !enabled }
        }
    }

    var showsTerminalProgressHint: Bool {
        isTerminalProgressHintNeeded && !preferences.terminalProgressHintDismissed
    }

    /// Opens the settings file in the preferred editor, or the agent folder when the file does not exist yet.
    func openPiSettingsFile() {
        let file = piSettings.settingsFile
        if FileManager.default.fileExists(atPath: file.path) {
            externalApps.open(file, in: preferences.preferredEditor)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([piSettings.agentDirectory])
        }
    }

    func makeChangeSetModel() -> ChangeSetModel {
        ChangeSetModel(git: git, writer: gitWriter)
    }

    /// Marks the task so its dot appears, and notifies only when PiBoard is not the app the user
    /// is looking at. A task whose terminal is already on screen is neither marked nor announced.
    private func agentSettled(taskID: UUID) {
        lastSettledTaskID = taskID
        settleRevision += 1
        refreshSummary(taskID: taskID)
        guard let task = board.tasks.first(where: { $0.id == taskID }) else { return }
        let isWatching = NSApplication.shared.isActive && board.openTerminalTaskID == taskID
        guard !isWatching else { return }

        attention.mark(taskID: taskID)
        Diagnostics.ui.notice("agent settled task=\(taskID.uuidString, privacy: .public)")
        guard !NSApplication.shared.isActive else { return }

        let projectName = board.projects.first { $0.id == task.projectId }?.name ?? ""
        let notifications = notifications
        Task {
            await notifications.notifyAgentFinished(
                taskTitle: task.title,
                projectName: projectName,
                target: AgentNotificationTarget(projectID: task.projectId, taskID: taskID)
            )
        }
    }

    /// Same as `agentSettled` for an agent blocked on a permission or question.
    private func agentNeedsInput(taskID: UUID) {
        guard let task = board.tasks.first(where: { $0.id == taskID }) else { return }
        let isWatching = NSApplication.shared.isActive && board.openTerminalTaskID == taskID
        guard !isWatching else { return }

        Diagnostics.ui.notice("agent needs input task=\(taskID.uuidString, privacy: .public)")
        guard !NSApplication.shared.isActive else { return }

        let projectName = board.projects.first { $0.id == task.projectId }?.name ?? ""
        let notifications = notifications
        Task {
            await notifications.notifyAgentNeedsInput(
                taskTitle: task.title,
                projectName: projectName,
                target: AgentNotificationTarget(projectID: task.projectId, taskID: taskID)
            )
        }
    }

    /// Re-reads the session file of one task; called when its agent settled or its process exited.
    func refreshSummary(taskID: UUID) {
        guard let task = board.tasks.first(where: { $0.id == taskID }),
              let project = board.projects.first(where: { $0.id == task.projectId }) else { return }
        sessionSummaries.refresh(task: task, project: project)
    }

    /// Entry point for a click on a delivered notification: selects the project, the task, and
    /// opens its terminal, then drops the mark because the user has now seen it.
    func open(_ target: AgentNotificationTarget) {
        guard board.tasks.contains(where: { $0.id == target.taskID }) else { return }
        board.selectedProjectID = target.projectID
        board.selectedTaskID = target.taskID
        // Through openTerminal so the inspector is dismissed and the detail swap is deferred,
        // the same as a click on a card.
        board.openTerminal(for: target.taskID)
        attention.clear(taskID: target.taskID)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// The find bar belongs to the terminal that is on screen; a session running in the
    /// background has no view to show it in.
    var canShowTerminalFindBar: Bool {
        board.openTerminalTaskID.flatMap(processes.session(for:)) != nil
    }

    func showTerminalFindBar() {
        guard let taskID = board.openTerminalTaskID, let session = processes.session(for: taskID) else { return }
        session.terminalView.showFindBar()
    }

    /// The drawer belongs to the selected project, on its board or on one of its task terminals.
    var canToggleTerminalDrawer: Bool { board.selectedProjectID != nil }

    func toggleTerminalDrawer() {
        guard canToggleTerminalDrawer else { return }
        board.isTerminalDrawerPresented.toggle()
    }

    /// The task a task-level shortcut applies to: the terminal on screen, else the selected card.
    private var shortcutTaskID: UUID? {
        board.openTerminalTaskID ?? board.selectedTaskID
    }

    /// Routes a recorded shortcut; each case checks the same precondition its button has.
    func perform(_ action: ShortcutAction) {
        switch action {
        case .toggleTerminal:
            toggleTerminalDrawer()
        case .newTask:
            guard board.openTerminalTaskID == nil, board.selectedProjectID != nil else { return }
            board.isNewTaskSheetPresented = true
        case .backToBoard:
            board.openTerminalTaskID = nil
        case .toggleInspector:
            guard board.openTerminalTaskID == nil, board.selectedProjectID != nil else { return }
            board.isInspectorPresented.toggle()
        case .toggleChanges:
            guard board.openTerminalTaskID != nil else { return }
            board.isChangesPanelPresented.toggle()
        case .stopPi:
            guard let taskID = shortcutTaskID, isTaskRunning(taskID) else { return }
            board.requestStop(taskID: taskID, agentActivity: processes.agentActivity(for: taskID)) { processes.stop(taskID: $0) }
        case .commandPalette:
            // One sheet at a time: the preparation and commit sheets own the window while they are up.
            guard board.pendingPreparationTaskID == nil, commits.request == nil else { return }
            board.isCommandPalettePresented = true
        }
    }

    /// Palette selection; the routing decision lives in CommandPaletteRouting so it is testable.
    func open(_ item: CommandPaletteItem) {
        board.isCommandPalettePresented = false
        switch item.kind {
        case .project(let project):
            board.selectedProjectID = project.id
            board.showBoard(for: project.id)
        case .task(let task, _):
            board.selectedProjectID = task.projectId
            board.selectedTaskID = task.id
            switch CommandPaletteRouting.destination(for: task, hasLiveSession: processes.session(for: task.id) != nil) {
            case .terminal: board.openTerminal(for: task.id)
            case .board: board.showBoard(for: task.projectId)
            }
        }
    }

    // A task already stopping has nothing left to stop, so isActive is too wide here.
    private func isTaskRunning(_ taskID: UUID) -> Bool {
        let state = processes.runtimeState(for: taskID)
        return state == .running || state == .starting
    }

    /// Re-arms after every change because `withObservationTracking` fires only once.
    private func observeTerminalPreferences() {
        withObservationTracking {
            _ = preferences.terminalFontName
            _ = preferences.terminalFontSize
            _ = preferences.terminalLineHeightMultiplier
            _ = preferences.terminalCursorStyle
            _ = preferences.terminalOptionAsMeta
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let appearance = TerminalAppearance.make(from: self.preferences)
                self.processes.applyAppearanceToAllSessions(
                    appearance,
                    cursorStyle: self.preferences.terminalCursorStyle,
                    optionAsMeta: self.preferences.terminalOptionAsMeta
                )
                self.shells.applyAppearanceToAllSessions(
                    appearance,
                    cursorStyle: self.preferences.terminalCursorStyle,
                    optionAsMeta: self.preferences.terminalOptionAsMeta
                )
                self.observeTerminalPreferences()
            }
        }
    }

    func stopOrphanedProcesses() {
        let entries = orphanedProcesses
        orphanedProcesses = []
        Task {
            await OrphanedProcessCleanup.stop(entries)
        }
    }

    func ignoreOrphanedProcesses() {
        orphanedProcesses = []
    }

    private nonisolated static let inMemoryPath = ":memory:"
    private nonisolated static let uiTestingRuntimeVersion = "0.0.0"
    private nonisolated static let uiTestingShell = "/bin/sh"
    private nonisolated static let corruptSuffix = ".corrupt-"
    private nonisolated static let corruptTimestampFormat = "yyyyMMdd-HHmmss"
    private nonisolated static let posixLocaleIdentifier = "en_US_POSIX"
    private nonisolated static let sidecarSuffixes = ["-wal", "-shm"]
    private nonisolated static let corruptionCodes: Set<Int32> = [SQLITE_CORRUPT, SQLITE_NOTADB]
    // SQLite extended result codes keep the primary code in the low byte.
    private nonisolated static let primaryResultCodeMask: Int32 = 0xFF

    /// Opens and migrates the database at `url`. A corrupt file (and its WAL/SHM sidecars) is
    /// moved aside and replaced by a fresh database; any other failure falls back to memory.
    nonisolated static func openOrRecover(at url: URL) -> (Database, recoveryNote: String?) {
        do {
            return (try openAndMigrate(path: url.path), nil)
        } catch let error as DatabaseError where isCorruption(error) {
            let backup: URL
            do {
                backup = try moveAside(url)
            } catch {
                return (inMemoryDatabase(), "The PiBoard database at \(url.path) is damaged and could not be moved aside. Changes will not be saved.")
            }
            do {
                return (
                    try openAndMigrate(path: url.path),
                    "The PiBoard database was damaged and has been replaced with an empty one. The old file was moved to \(backup.path)."
                )
            } catch {
                return (inMemoryDatabase(), "The PiBoard database was damaged; the old file was moved to \(backup.path), but a new one could not be created. Changes will not be saved.")
            }
        } catch {
            return (inMemoryDatabase(), "Could not open the PiBoard database at \(url.path). Changes will not be saved.")
        }
    }

    private nonisolated static func openAndMigrate(path: String) throws -> Database {
        let database = try Database(path: path)
        try MigrationRunner.migrate(database)
        return database
    }

    private nonisolated static func installFakeRuntime(entry: URL, into paths: AgentRuntimePaths) throws {
        let destination = paths.entry(for: uiTestingRuntimeVersion)
        let files = FileManager.default
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.copyItem(at: entry, to: destination)
        let pointer = CurrentPointer(activeVersion: uiTestingRuntimeVersion, previousVersion: nil)
        try files.createDirectory(at: paths.currentPointerFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(pointer).write(to: paths.currentPointerFile)
    }

    private static func installFakeTool(from source: URL, into destination: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in try files.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey]) {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let target = destination.appendingPathComponent(file.lastPathComponent)
            try Data(contentsOf: file).write(to: target)
            try files.setAttributes([.posixPermissions: fakeExecutablePermissions], ofItemAtPath: target.path)
        }
    }

    // Demo paths point into the real home folder; terminals need directories that exist.
    private static func giveProjectsRealFolders(in board: BoardModel, testing: TestingConfiguration) {
        for project in board.projects {
            guard let folder = testing.projectFolder(named: project.name) else { continue }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            board.updateProject(id: project.id, name: project.name, path: folder)
        }
    }

    private nonisolated static func inMemoryDatabase() -> Database {
        let database = try! Database(path: inMemoryPath)
        try? MigrationRunner.migrate(database)
        return database
    }

    private nonisolated static func isCorruption(_ error: DatabaseError) -> Bool {
        guard case .sqlite(let code, _) = error else { return false }
        return corruptionCodes.contains(code & primaryResultCodeMask)
    }

    /// Returns the new location of the main file; sidecars get the same suffix. A WAL left in
    /// place would be replayed into the fresh database, so a failed sidecar move is an error.
    private nonisolated static func moveAside(_ url: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: posixLocaleIdentifier)
        formatter.dateFormat = corruptTimestampFormat
        let suffix = corruptSuffix + formatter.string(from: Date())
        let fileManager = FileManager.default
        let backup = URL(fileURLWithPath: url.path + suffix)
        try fileManager.moveItem(at: url, to: backup)
        for sidecar in sidecarSuffixes {
            let source = URL(fileURLWithPath: url.path + sidecar)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: URL(fileURLWithPath: source.path + suffix))
        }
        return backup
    }
}
