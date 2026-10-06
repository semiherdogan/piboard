enum MigrationRunner {
    static let all: [Migration] = [
        Migration001_InitialSchema.migration
    ]

    static func migrate(_ db: Database) throws {
        try db.perform { connection in
            let currentVersion = connection.userVersion
            for migration in all where migration.version > currentVersion {
                try connection.transaction {
                    try connection.execute(sql: migration.sql)
                    connection.userVersion = migration.version
                }
            }
        }
    }
}
