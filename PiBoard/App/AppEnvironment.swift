import Foundation
import Observation

// Composition root for services; populated as milestones land.
@MainActor
@Observable
final class AppEnvironment {
    let piRuntime = PiRuntimeManager()
    let board: BoardModel
    let preferences: AppPreferences
    let processes: PiProcessManager
    let git: GitServicing
    let worktrees: WorktreeServicing
    let externalApps: ExternalAppActions
    let worktreeActions: WorktreeActions
    // Set when the on-disk database could not be opened; the app falls back to an
    // in-memory database so the UI still works, but nothing persists across launches.
    var startupError: String?

    init() {
        var openedError: Error?
        let database = Self.openDatabase(error: &openedError)
        if let openedError {
            startupError = "Could not open the PiBoard database at \((try? AppPaths.databaseURL())?.path ?? "unknown path"). Changes will not be saved."
        }
        let board = BoardModel(database: database)
        self.board = board
        externalApps = ExternalAppActions(service: ExternalAppService(), board: board)
        let preferences = AppPreferences(database: database)
        self.preferences = preferences
        let processes = PiProcessManager(makeSession: {
            let appearance = TerminalAppearance.make(from: preferences)
            let session = PTYSession(appearance: appearance, scrollbackLines: preferences.terminalScrollbackLines)
            session.apply(
                appearance,
                cursorStyle: preferences.terminalCursorStyle,
                optionAsMeta: preferences.terminalOptionAsMeta
            )
            return session
        })
        self.processes = processes
        let git = GitService()
        let worktrees = WorktreeService(rootDirectory: AppPaths.worktreesDirectory)
        self.git = git
        self.worktrees = worktrees
        worktreeActions = WorktreeActions(board: board, processes: processes, git: git, worktrees: worktrees)
        piRuntime.refresh()
        observeTerminalPreferences()
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

    private static func openDatabase(error: inout Error?) -> Database {
        do {
            let databaseURL = try AppPaths.databaseURL()
            let database = try Database(path: databaseURL.path)
            try MigrationRunner.migrate(database)
            return database
        } catch let caught {
            error = caught
            let fallback = try! Database(path: ":memory:")
            try? MigrationRunner.migrate(fallback)
            return fallback
        }
    }
}
