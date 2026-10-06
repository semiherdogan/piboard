enum SettingKey: String {
    case lastOpenedProjectID = "last_opened_project_id"
    case planFirstSuffix = "plan_first_suffix"
    case planFirstEnabled = "plan_first_enabled"
}

final class SettingsRepository {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func get(_ key: SettingKey) -> String? {
        let result: String?? = try? database.perform { connection in
            let statement = try connection.prepare("SELECT value FROM settings WHERE key = ?;")
            statement.bind(key.rawValue, at: 1)
            guard try statement.step() else { return nil }
            return statement.columnOptionalString(at: 0)
        }
        return result ?? nil
    }

    func set(_ key: SettingKey, value: String) throws {
        try database.perform { connection in
            let statement = try connection.prepare(
                "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
            )
            statement.bind(key.rawValue, at: 1)
            statement.bind(value, at: 2)
            try statement.step()
        }
    }

    func getBool(_ key: SettingKey) -> Bool? {
        guard let stored = get(key) else { return nil }
        return stored == "true"
    }

    func setBool(_ key: SettingKey, value: Bool) throws {
        try set(key, value: value ? "true" : "false")
    }
}
