// Existing projects keep the order they had, which was creation order; the id breaks ties.
enum Migration006_ProjectPosition {
    static let migration = Migration(
        version: 6,
        sql: """
        ALTER TABLE projects ADD COLUMN position INTEGER NOT NULL DEFAULT 0;
        UPDATE projects SET position = (
            SELECT COUNT(*) FROM projects AS earlier
            WHERE earlier.created_at < projects.created_at
               OR (earlier.created_at = projects.created_at AND earlier.id < projects.id)
        );
        """
    )
}
