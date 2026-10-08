import AppKit
import Foundation
import Observation
import SQLite3

// Composition root for services; populated as milestones land.
@MainActor
@Observable
final class AppEnvironment {

    let piRuntime: PiRuntimeManager
    let board: BoardModel
    let preferences: AppPreferences
    let processes: PiProcessManager
    let git: GitServicing
    let worktrees: WorktreeServicing
    let externalApps: ExternalAppActions
    let worktreeActions: WorktreeActions
    let deletions: DeletionActions
    let commits: CommitActions
    let updates: UpdateService
    let attention: TaskAttention
    let notifications: any AgentNotifying
    // Set when the on-disk database was replaced after corruption, or could not be opened at
    // all (then the app runs on an in-memory database and nothing persists across launches).
    var startupError: String?
    // Pi children left running by a PiBoard run that crashed or was force-quit; shown once.
    var orphanedProcesses: [LiveProcessEntry] = []

    init() {
        // Set by XCTest in the hosted app; unit tests must not reach the npm registry.
        let isRunningTests = ProcessInfo.processInfo.environment[LaunchEnvironment.testConfigurationEnvKey] != nil
        // Resolving the login shell spawns a process, so it starts now and runs while the
        // database opens, rather than blocking the first Pi launch.
        LaunchEnvironment.prewarm()
        let database: Database
        do {
            let opened = Self.openOrRecover(at: try AppPaths.databaseURL())
            database = opened.0
            startupError = opened.recoveryNote
        } catch {
            database = Self.inMemoryDatabase()
            startupError = "Could not locate the PiBoard database folder: \(error.localizedDescription). Changes will not be saved."
        }
        // Hosted tests must never read or clear the real registry of a running PiBoard.
        let liveProcesses = isRunningTests ? nil : (try? LiveProcessRegistry.defaultFileURL()).map(LiveProcessRegistry.init(fileURL:))
        if let liveProcesses {
            orphanedProcesses = OrphanedProcessCleanup.orphans(
                in: liveProcesses.entries,
                expectedExecutable: (try? BundledNode.locate())?.nodeExecutable
            )
            liveProcesses.clear()
        }
        piRuntime = PiRuntimeManager(settings: SettingsRepository(database: database))
        // Hosted tests must not start Sparkle, so they see the build as unconfigured.
        updates = UpdateService(
            settings: SettingsRepository(database: database),
            publicEDKey: isRunningTests ? nil : Bundle.main.object(forInfoDictionaryKey: BundleInfoKey.sparklePublicEDKey) as? String,
            makeUpdater: { SparkleUpdater(allowedChannels: $0, onStateChange: $1) }
        )
        let board = BoardModel(database: database)
        self.board = board
        attention = TaskAttention()
        // Hosted tests must not ask the user for notification permission.
        notifications = isRunningTests ? NoNotifications() : AgentNotificationService()
        externalApps = ExternalAppActions(service: ExternalAppService(), board: board)
        let preferences = AppPreferences(database: database)
        self.preferences = preferences
        let externalApps = self.externalApps
        let makeSession: @MainActor () -> PTYSession = {
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
        let processes = PiProcessManager(makeSession: makeSession, liveProcesses: liveProcesses)
        self.processes = processes
        piRuntime.versionsInUse = { processes.versionsInUse }
        let git = GitService()
        let worktrees = WorktreeService(rootDirectory: AppPaths.worktreesDirectory)
        self.git = git
        self.worktrees = worktrees
        worktreeActions = WorktreeActions(board: board, processes: processes, git: git, worktrees: worktrees)
        deletions = DeletionActions(board: board, processes: processes, worktrees: worktrees, attention: attention)
        let piRuntime = piRuntime
        commits = CommitActions(
            git: git,
            writer: GitWriteService(),
            terminal: GitTerminalRunner(makeSession: makeSession),
            generator: PiCommitMessageGenerator(launch: {
                let node = try BundledNode.locate()
                return (node.nodeExecutable, try piRuntime.activeEntry().entry)
            })
        )
        processes.onAgentSettled = { [weak self] taskID in
            self?.agentSettled(taskID: taskID)
        }
        piRuntime.refresh()
        if !isRunningTests {
            piRuntime.checkForUpdatesIfDue()
            Task { await notifications.requestAuthorization() }
        }
        observeTerminalPreferences()
    }

    /// Marks the task so its dot appears, and notifies only when PiBoard is not the app the user
    /// is looking at. A task whose terminal is already on screen is neither marked nor announced.
    private func agentSettled(taskID: UUID) {
        guard let task = board.tasks.first(where: { $0.id == taskID }) else { return }
        let isWatching = NSApplication.shared.isActive && board.openTerminalTaskID == taskID
        guard !isWatching else { return }

        attention.mark(taskID: taskID)
        Diagnostics.ui.info("agent settled task=\(taskID.uuidString, privacy: .public)")
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

    /// Entry point for a click on a delivered notification: selects the project, the task, and
    /// opens its terminal, then drops the mark because the user has now seen it.
    func open(_ target: AgentNotificationTarget) {
        guard board.tasks.contains(where: { $0.id == target.taskID }) else { return }
        board.selectedProjectID = target.projectID
        board.selectedTaskID = target.taskID
        board.openTerminalTaskID = target.taskID
        attention.clear(taskID: target.taskID)
        NSApplication.shared.activate(ignoringOtherApps: true)
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
                self.processes.applyAppearanceToAllSessions(
                    TerminalAppearance.make(from: self.preferences),
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
