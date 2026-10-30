import Foundation
import Testing
@testable import PiBoard

struct MigrationRunnerTests {
    @Test func freshDatabaseEndsUpAtTheLatestVersion() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)

        let version = database.perform { $0.userVersion }
        #expect(version == MigrationRunner.all.last!.version)
    }

    @Test func migratingTwiceIsANoOp() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        try MigrationRunner.migrate(database)

        let version = database.perform { $0.userVersion }
        #expect(version == MigrationRunner.all.last!.version)
    }

    @Test func schemaContainsExpectedTablesAndIndex() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)

        let names: [String] = try database.perform { connection in
            let statement = try connection.prepare(
                "SELECT name FROM sqlite_master WHERE type IN ('table', 'index') ORDER BY name;"
            )
            var names: [String] = []
            while try statement.step() {
                names.append(try statement.column("name", at: 0))
            }
            return names
        }

        #expect(names.contains("projects"))
        #expect(names.contains("tasks"))
        #expect(names.contains("settings"))
        #expect(names.contains("tasks_project_status_position"))
    }

    @Test func agentColumnsExistAfterMigrating() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)

        #expect(database.perform { $0.userVersion } >= Migration003_AgentColumns.migration.version)
        #expect(try columnNames(of: "tasks", in: database).contains("agent"))
        #expect(try columnNames(of: "projects", in: database).contains("default_agent"))
    }

    @Test func previousSessionColumnsExistAfterMigrating() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)

        #expect(database.perform { $0.userVersion } == Migration004_PreviousSession.migration.version)
        let columns = try columnNames(of: "tasks", in: database)
        #expect(columns.contains("previous_agent"))
        #expect(columns.contains("previous_session_id"))
    }

    @Test func taskCreatedAtVersionThreeReadsWithNilPreviousFieldsAfterMigrating() throws {
        let database = try Database(path: ":memory:")
        try database.perform { connection in
            for migration in [Migration001_InitialSchema.migration, Migration002_NormalizeTaskPositions.migration, Migration003_AgentColumns.migration] {
                try connection.execute(sql: migration.sql)
                connection.userVersion = migration.version
            }
        }

        let projectID = UUID()
        try database.perform { connection in
            let project = try connection.prepare(
                "INSERT INTO projects (id, name, path, created_at, updated_at) VALUES (?, 'A', '/tmp/a', ?, ?);"
            )
            project.bind(projectID.uuidString.uppercased(), at: 1)
            project.bind("2024-01-01T00:00:00.000Z", at: 2)
            project.bind("2024-01-01T00:00:00.000Z", at: 3)
            try project.step()
            let task = try connection.prepare(
                """
                INSERT INTO tasks (id, project_id, title, status, position, created_at, updated_at)
                VALUES (?, ?, 'T', 'backlog', 0, ?, ?);
                """
            )
            task.bind(UUID().uuidString.uppercased(), at: 1)
            task.bind(projectID.uuidString.uppercased(), at: 2)
            task.bind("2024-01-01T00:00:00.000Z", at: 3)
            task.bind("2024-01-01T00:00:00.000Z", at: 4)
            try task.step()
        }

        try MigrationRunner.migrate(database)

        let tasks = try TaskRepository(database: database).fetchAll(projectID: projectID)
        #expect(tasks.count == 1)
        #expect(tasks.first?.previousAgent == nil)
        #expect(tasks.first?.previousSessionID == nil)
    }

    @Test func taskCreatedAtVersionTwoReadsAsPiAfterMigrating() throws {
        let database = try Database(path: ":memory:")
        try database.perform { connection in
            try connection.execute(sql: Migration001_InitialSchema.migration.sql)
            try connection.execute(sql: Migration002_NormalizeTaskPositions.migration.sql)
            connection.userVersion = Migration002_NormalizeTaskPositions.migration.version
        }

        let projectID = UUID()
        try database.perform { connection in
            let project = try connection.prepare(
                "INSERT INTO projects (id, name, path, created_at, updated_at) VALUES (?, 'A', '/tmp/a', ?, ?);"
            )
            project.bind(projectID.uuidString.uppercased(), at: 1)
            project.bind("2024-01-01T00:00:00.000Z", at: 2)
            project.bind("2024-01-01T00:00:00.000Z", at: 3)
            try project.step()
            let task = try connection.prepare(
                """
                INSERT INTO tasks (id, project_id, title, status, position, created_at, updated_at)
                VALUES (?, ?, 'T', 'backlog', 0, ?, ?);
                """
            )
            task.bind(UUID().uuidString.uppercased(), at: 1)
            task.bind(projectID.uuidString.uppercased(), at: 2)
            task.bind("2024-01-01T00:00:00.000Z", at: 3)
            task.bind("2024-01-01T00:00:00.000Z", at: 4)
            try task.step()
        }

        try MigrationRunner.migrate(database)

        let tasks = try TaskRepository(database: database).fetchAll(projectID: projectID)
        #expect(tasks.map(\.agent) == [.pi])
        #expect(try ProjectRepository(database: database).fetchAll().map(\.defaultAgent) == [.pi])
    }

    private func columnNames(of table: String, in database: Database) throws -> [String] {
        try database.perform { connection in
            let statement = try connection.prepare("PRAGMA table_info(\(table));")
            var names: [String] = []
            while try statement.step() {
                names.append(try statement.column("name", at: 1))
            }
            return names
        }
    }

    @Test func migratingRenumbersInterleavedPositionsPerProjectAndStatus() throws {
        let database = try Database(path: ":memory:")
        try database.perform { connection in
            try connection.execute(sql: Migration001_InitialSchema.migration.sql)
            connection.userVersion = 1
        }

        let projectA = UUID()
        let projectB = UUID()
        try database.perform { connection in
            for (id, name) in [(projectA, "A"), (projectB, "B")] {
                let projectStatement = try connection.prepare(
                    "INSERT INTO projects (id, name, path, created_at, updated_at) VALUES (?, ?, ?, ?, ?);"
                )
                projectStatement.bind(id.uuidString.uppercased(), at: 1)
                projectStatement.bind(name, at: 2)
                projectStatement.bind("/tmp/\(name)", at: 3)
                projectStatement.bind("2024-01-01T00:00:00.000Z", at: 4)
                projectStatement.bind("2024-01-01T00:00:00.000Z", at: 5)
                try projectStatement.step()
            }
        }

        // Interleaved positions across two projects in the same status, matching the
        // corruption pattern seen with the pre-fix reorder logic.
        let seedRows: [(projectId: UUID, position: Int)] = [
            (projectA, 0),
            (projectB, 1),
            (projectA, 2),
            (projectB, 3),
            (projectA, 4),
            (projectA, 5)
        ]
        var firstProjectATaskID: UUID?
        try database.perform { connection in
            for (offset, row) in seedRows.enumerated() {
                let id = UUID()
                if row.projectId == projectA && firstProjectATaskID == nil {
                    firstProjectATaskID = id
                }
                let statement = try connection.prepare(
                    """
                    INSERT INTO tasks (id, project_id, title, status, position, created_at, updated_at)
                    VALUES (?, ?, 'T', 'backlog', ?, ?, ?);
                    """
                )
                statement.bind(id.uuidString.uppercased(), at: 1)
                statement.bind(row.projectId.uuidString.uppercased(), at: 2)
                statement.bind(row.position, at: 3)
                statement.bind("2024-01-01T00:00:0\(offset).000Z", at: 4)
                statement.bind("2024-01-01T00:00:0\(offset).000Z", at: 5)
                try statement.step()
            }
        }

        try MigrationRunner.migrate(database)

        #expect(database.perform { $0.userVersion } == MigrationRunner.all.last!.version)

        let repository = TaskRepository(database: database)
        let aTasks = try repository.fetchAll(projectID: projectA)
        let bTasks = try repository.fetchAll(projectID: projectB)
        #expect(aTasks.map(\.position) == [0, 1, 2, 3])
        #expect(bTasks.map(\.position) == [0, 1])
        #expect(aTasks.first?.id == firstProjectATaskID)
    }
}
