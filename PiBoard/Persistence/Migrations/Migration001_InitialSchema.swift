enum Migration001_InitialSchema {
    static let migration = Migration(
        version: 1,
        sql: """
        CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            path TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            prompt TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL CHECK(status IN ('backlog','in_progress','done')),
            position INTEGER NOT NULL,
            pi_session_id TEXT NULL,
            run_context TEXT NULL CHECK(run_context IN ('current','worktree') OR run_context IS NULL),
            worktree_path TEXT NULL,
            worktree_branch TEXT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE INDEX tasks_project_status_position ON tasks(project_id, status, position);
        """
    )
}
