import Foundation
import Testing
@testable import PiBoard

/// Guards the one thing that silently stops working in SQLite: `ON DELETE CASCADE` is declared in
/// the schema, but it only runs while `PRAGMA foreign_keys` is on for the connection. If that
/// pragma is ever dropped, deleting a project leaves its tasks behind as unreachable rows and
/// nothing above this layer notices.
@MainActor
struct ProjectDeletionCascadeTests {
    private func makeDatabase() throws -> Database {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        return database
    }

    private func taskCount(in database: Database, projectID: UUID? = nil) throws -> Int {
        try database.perform { connection in
            let statement = try projectID.map { id -> Statement in
                let statement = try connection.prepare("SELECT COUNT(*) FROM tasks WHERE project_id = ?;")
                statement.bind(id.uuidString, at: 1)
                return statement
            } ?? connection.prepare("SELECT COUNT(*) FROM tasks;")
            guard try statement.step() else { return 0 }
            return statement.columnInt(at: 0)
        }
    }

    @Test func foreignKeyEnforcementIsOnForTheConnection() throws {
        let database = try makeDatabase()
        let isEnabled = try database.perform { connection in
            let statement = try connection.prepare("PRAGMA foreign_keys;")
            guard try statement.step() else { return 0 }
            return statement.columnInt(at: 0)
        }
        #expect(isEnabled == 1)
    }

    /// `addProject` does not hand the project back, so it is read off the model after the insert.
    private func addProject(_ name: String, to model: BoardModel) -> Project? {
        model.addProject(name: name, path: URL(fileURLWithPath: "/tmp/\(name)"))
        return model.projects.last { $0.name == name }
    }

    @Test func deletingAProjectRemovesItsTaskRows() throws {
        let database = try makeDatabase()
        let model = BoardModel(database: database)
        guard let project = addProject("Doomed", to: model) else {
            Issue.record("expected the project to be created")
            return
        }
        for title in ["First", "Second", "Third"] {
            model.addTask(title: title, prompt: "", to: project.id)
        }
        // Without this the assertion below would pass on an empty table and prove nothing.
        #expect(try taskCount(in: database, projectID: project.id) == 3)

        model.deleteProject(id: project.id)

        #expect(try taskCount(in: database, projectID: project.id) == 0)
        #expect(try taskCount(in: database) == 0)
    }

    @Test func tasksOfOtherProjectsSurvive() throws {
        let database = try makeDatabase()
        let model = BoardModel(database: database)
        guard let doomed = addProject("Doomed", to: model), let kept = addProject("Kept", to: model) else {
            Issue.record("expected both projects to be created")
            return
        }
        model.addTask(title: "Goes away", prompt: "", to: doomed.id)
        model.addTask(title: "Stays", prompt: "", to: kept.id)

        model.deleteProject(id: doomed.id)

        #expect(try taskCount(in: database, projectID: doomed.id) == 0)
        #expect(try taskCount(in: database, projectID: kept.id) == 1)
    }

    // A row whose project is gone would still be loaded by any future query that does not filter
    // by project, so the check is made against the whole table rather than the model's view.
    @Test func noTaskRowOutlivesItsProject() throws {
        let database = try makeDatabase()
        let model = BoardModel(database: database)
        guard let project = addProject("Doomed", to: model) else {
            Issue.record("expected the project to be created")
            return
        }
        model.addTask(title: "Orphan candidate", prompt: "", to: project.id)
        model.deleteProject(id: project.id)

        let orphans = try database.perform { connection in
            let statement = try connection.prepare(
                "SELECT COUNT(*) FROM tasks WHERE project_id NOT IN (SELECT id FROM projects);"
            )
            guard try statement.step() else { return 0 }
            return statement.columnInt(at: 0)
        }
        #expect(orphans == 0)
    }
}
