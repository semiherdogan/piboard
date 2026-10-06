enum Migration002_NormalizeTaskPositions {
    // Backfill for positions that drifted out of 0..<N per (project, status) before the
    // ordering bug in TaskOrdering.reorder was fixed; re-running this is a no-op since the
    // ranks it assigns are already 0..<N.
    static let migration = Migration(
        version: 2,
        sql: """
        UPDATE tasks
        SET position = ranked.new_position
        FROM (
            SELECT id, ROW_NUMBER() OVER (
                PARTITION BY project_id, status
                ORDER BY position, created_at
            ) - 1 AS new_position
            FROM tasks
        ) AS ranked
        WHERE tasks.id = ranked.id;
        """
    )
}
