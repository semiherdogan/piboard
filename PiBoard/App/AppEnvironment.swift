import Foundation
import Observation

// Composition root for services; populated as milestones land.
@MainActor
@Observable
final class AppEnvironment {
    let piRuntime = PiRuntimeManager()
    let board: BoardModel
    let processes = PiProcessManager()
    // Set when the on-disk database could not be opened; the app falls back to an
    // in-memory database so the UI still works, but nothing persists across launches.
    var startupError: String?

    init() {
        var openedError: Error?
        let database = Self.openDatabase(error: &openedError)
        if let openedError {
            startupError = "Could not open the PiBoard database at \((try? AppPaths.databaseURL())?.path ?? "unknown path"). Changes will not be saved."
        }
        board = BoardModel(database: database)
        piRuntime.refresh()
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
