enum SettingKey: String {
    case lastOpenedProjectID = "last_opened_project_id"
    case planFirstSuffix = "plan_first_suffix"
    case planFirstEnabled = "plan_first_enabled"
    case terminalFontName = "terminal_font_name"
    case terminalFontSize = "terminal_font_size"
    case terminalLineHeightMultiplier = "terminal_line_height_multiplier"
    case terminalCursorStyle = "terminal_cursor_style"
    case terminalScrollbackLines = "terminal_scrollback_lines"
    case terminalOptionAsMeta = "terminal_option_as_meta"
    case changesPanelWidth = "changes_panel_width"
    case preferredEditor = "preferred_editor"
    case preferredTerminal = "preferred_terminal"
    case piLatestKnownVersion = "pi_latest_known_version"
    case piLastUpdateCheckAt = "pi_last_update_check_at"
    case updateChannel = "update_channel"
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

    func getInt(_ key: SettingKey) -> Int? {
        get(key).flatMap { Int($0) }
    }

    func setInt(_ key: SettingKey, value: Int) throws {
        try set(key, value: String(value))
    }

    func getDouble(_ key: SettingKey) -> Double? {
        get(key).flatMap { Double($0) }
    }

    func setDouble(_ key: SettingKey, value: Double) throws {
        try set(key, value: String(value))
    }
}
