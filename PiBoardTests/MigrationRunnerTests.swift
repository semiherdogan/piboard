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
}
