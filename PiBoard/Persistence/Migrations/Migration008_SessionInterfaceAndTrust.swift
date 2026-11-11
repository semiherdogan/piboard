/// A task picks terminal or native chat; a project records whether the user trusts its Pi resources.
enum Migration008_SessionInterfaceAndTrust {
    static let migration = Migration(
        version: 8,
        sql: """
        ALTER TABLE tasks ADD COLUMN interface TEXT NOT NULL DEFAULT 'terminal';
        ALTER TABLE projects ADD COLUMN trusts_pi_resources INTEGER NOT NULL DEFAULT 0;
        """
    )
}
