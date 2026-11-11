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

        #expect(database.perform { $0.userVersion } >= Migration004_PreviousSession.migration.version)
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

    @Test func interfaceAndTrustColumnsExistAfterMigrating() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)

        #expect(database.perform { $0.userVersion } >= Migration008_SessionInterfaceAndTrust.migration.version)
        #expect(try columnNames(of: "tasks", in: database).contains("interface"))
        #expect(try columnNames(of: "projects", in: database).contains("trusts_pi_resources"))
    }

    @Test func rowsCreatedAtVersionSevenReadAsTerminalAndUntrusted() throws {
        let database = try Database(path: ":memory:")
        let before = MigrationRunner.all.filter { $0.version < Migration008_SessionInterfaceAndTrust.migration.version }
        try database.perform { connection in
            for migration in before {
                try connection.execute(sql: migration.sql)
                connection.userVersion = migration.version
            }
            let timestamp = "2024-01-01T00:00:00.000Z"
            try connection.execute(sql: """
                INSERT INTO projects (id, name, path, created_at, updated_at)
                VALUES ('\(seededProjectID.uuidString)', 'A', '/tmp/a', '\(timestamp)', '\(timestamp)');
                INSERT INTO tasks (id, project_id, title, status, position, created_at, updated_at)
                VALUES ('00000000-0000-0000-0000-000000000002', '\(seededProjectID.uuidString)', 'T', 'backlog', 0, '\(timestamp)', '\(timestamp)');
                """)
        }

        try MigrationRunner.migrate(database)

        #expect(try TaskRepository(database: database).fetchAll(projectID: seededProjectID).map(\.interface) == [.terminal])
        #expect(try ProjectRepository(database: database).fetchAll().map(\.trustsPiResources) == [false])
    }

    @Test func projectsCreatedBeforePositionsKeepTheirCreationOrder() throws {
        let database = try Database(path: ":memory:")
        let preposition = MigrationRunner.all.filter { $0.version < Migration006_ProjectPosition.migration.version }
        try database.perform { connection in
            for migration in preposition {
                try connection.execute(sql: migration.sql)
                connection.userVersion = migration.version
            }
        }
        // Inserted newest first so the old ORDER BY created_at and the insertion order disagree.
        let createdAt = ["2024-03-01T00:00:00.000Z", "2024-01-01T00:00:00.000Z", "2024-02-01T00:00:00.000Z"]
        let ids = createdAt.map { _ in UUID() }
        try database.perform { connection in
            for (id, date) in zip(ids, createdAt) {
                let project = try connection.prepare(
                    "INSERT INTO projects (id, name, path, created_at, updated_at) VALUES (?, 'P', '/tmp/p', ?, ?);"
                )
                project.bind(id.uuidString.uppercased(), at: 1)
                project.bind(date, at: 2)
                project.bind(date, at: 3)
                try project.step()
            }
        }

        try MigrationRunner.migrate(database)

        #expect(try ProjectRepository(database: database).fetchAll().map(\.id) == [ids[1], ids[2], ids[0]])
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

    // The PiG engine (migration 5) and the PiG agent (retired in migration 7) both end on Pi.
    @MainActor
    @Test func aPigEngineDatabaseEndsUpOnPi() throws {
        let database = try databaseAtVersionFour(settings: [
            ("pi_engine", "pig"),
            ("commit_message_agent", "pi"),
            ("enabled_agents", #"["opencode","pi"]"#),
            ("agent_executable_paths", #"{"pi":"/opt/pig","opencode":"/opt/opencode"}"#),
        ])

        try MigrationRunner.migrate(database)

        let settings = SettingsRepository(database: database)
        let tasks = try TaskRepository(database: database).fetchAll(projectID: seededProjectID)
        #expect(tasks.map(\.agent) == [.pi])
        #expect(tasks.first?.previousAgent == .pi)
        #expect(try ProjectRepository(database: database).fetchAll().map(\.defaultAgent) == [.pi])
        #expect(settings.get(.commitMessageAgent) == AgentKind.pi.rawValue)
        #expect(settings.get(.enabledAgents).map(jsonStrings) == ["opencode", "pi"])
        #expect(AppPreferences.decodeExecutablePaths(settings.get(.agentExecutablePaths)) == [.opencode: "/opt/opencode"])
        #expect(try engineSettingRowCount(in: database) == 0)
    }

    @MainActor
    @Test func anEnabledListOfOnlyPigFallsBackToPi() throws {
        let database = try databaseAtVersionFour(settings: [("enabled_agents", #"["pig"]"#)])

        try MigrationRunner.migrate(database)

        #expect(SettingsRepository(database: database).get(.enabledAgents).map(jsonStrings) == ["pi"])
    }

    @MainActor
    @Test func piEngineSettingLeavesTasksAlone() throws {
        let database = try databaseAtVersionFour(settings: [("pi_engine", "pi")])

        try MigrationRunner.migrate(database)

        let settings = SettingsRepository(database: database)
        let tasks = try TaskRepository(database: database).fetchAll(projectID: seededProjectID)
        #expect(tasks.map(\.agent) == [.pi])
        #expect(tasks.first?.previousAgent == .pi)
        #expect(settings.get(.commitMessageAgent) == nil)
        #expect(try ProjectRepository(database: database).fetchAll().map(\.defaultAgent) == [.pi])
        #expect(try engineSettingRowCount(in: database) == 0)
    }

    private func jsonStrings(_ json: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }

    private let seededProjectID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func databaseAtVersionFour(settings: [(key: String, value: String)]) throws -> Database {
        let database = try Database(path: ":memory:")
        try database.perform { connection in
            for migration in [
                Migration001_InitialSchema.migration,
                Migration002_NormalizeTaskPositions.migration,
                Migration003_AgentColumns.migration,
                Migration004_PreviousSession.migration,
            ] {
                try connection.execute(sql: migration.sql)
                connection.userVersion = migration.version
            }
            let timestamp = "2024-01-01T00:00:00.000Z"
            try connection.execute(sql: """
                INSERT INTO projects (id, name, path, created_at, updated_at)
                VALUES ('\(seededProjectID.uuidString)', 'A', '/tmp/a', '\(timestamp)', '\(timestamp)');
                INSERT INTO tasks (id, project_id, title, status, position, created_at, updated_at, previous_agent, previous_session_id)
                VALUES ('00000000-0000-0000-0000-000000000002', '\(seededProjectID.uuidString)', 'T', 'backlog', 0, '\(timestamp)', '\(timestamp)', 'pi', 'old');
                """)
            for setting in settings {
                let insert = try connection.prepare("INSERT INTO settings (key, value) VALUES (?, ?);")
                insert.bind(setting.key, at: 1)
                insert.bind(setting.value, at: 2)
                try insert.step()
            }
        }
        return database
    }

    private func engineSettingRowCount(in database: Database) throws -> Int {
        try database.perform { connection in
            let statement = try connection.prepare("SELECT COUNT(*) FROM settings WHERE key = 'pi_engine';")
            _ = try statement.step()
            return statement.columnInt(at: 0)
        }
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
