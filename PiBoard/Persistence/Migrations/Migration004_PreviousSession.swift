enum Migration004_PreviousSession {
    static let migration = Migration(
        version: 4,
        sql: """
        ALTER TABLE tasks ADD COLUMN previous_agent TEXT NULL;
        ALTER TABLE tasks ADD COLUMN previous_session_id TEXT NULL;
        """
    )
}
