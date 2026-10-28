enum Migration003_AgentColumns {
    static let migration = Migration(
        version: 3,
        sql: """
        ALTER TABLE tasks ADD COLUMN agent TEXT NOT NULL DEFAULT 'pi';
        ALTER TABLE projects ADD COLUMN default_agent TEXT NOT NULL DEFAULT 'pi';
        """
    )
}
