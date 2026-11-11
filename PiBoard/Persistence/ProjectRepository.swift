import Foundation

final class ProjectRepository {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func fetchAll() throws -> [Project] {
        try database.perform { connection in
            let statement = try connection.prepare(
                "SELECT id, name, path, created_at, updated_at, default_agent, trusts_pi_resources FROM projects ORDER BY position, created_at;"
            )
            var rows: [Project] = []
            while try statement.step() {
                rows.append(try ProjectRow.read(from: statement))
            }
            return rows
        }
    }

    func insert(_ project: Project) throws {
        try database.perform { connection in
            try Self.insert(project, on: connection)
        }
    }

    /// Inserts the project and its tasks atomically so a failed import leaves nothing behind.
    func insert(_ project: Project, tasks: [BoardTask]) throws {
        try database.perform { connection in
            try connection.transaction {
                try Self.insert(project, on: connection)
                for task in tasks {
                    try TaskRepository.insert(task, on: connection)
                }
            }
        }
    }

    private static func insert(_ project: Project, on connection: Connection) throws {
        let statement = try connection.prepare(
            // A new project goes to the bottom of the sidebar.
            "INSERT INTO projects (id, name, path, created_at, updated_at, default_agent, trusts_pi_resources, position) VALUES (?, ?, ?, ?, ?, ?, ?, (SELECT COALESCE(MAX(position), -1) + 1 FROM projects));"
        )
        ProjectRow.bind(project, to: statement)
        try statement.step()
    }

    func update(_ project: Project) throws {
        try database.perform { connection in
            let lookup = try connection.prepare("SELECT default_agent FROM projects WHERE id = ?;")
            lookup.bind(project.id.uuidString.uppercased(), at: 1)
            var storedAgent: String?
            if try lookup.step() {
                storedAgent = try lookup.column("default_agent", at: 0)
            }
            // The in-memory .default is only the read fallback for an unknown stored value, so a rename must not overwrite it.
            var agentToStore = project.defaultAgent.rawValue
            if let storedAgent, AgentKind(rawValue: storedAgent) == nil, project.defaultAgent == .default {
                agentToStore = storedAgent
            }
            let statement = try connection.prepare(
                "UPDATE projects SET name = ?, path = ?, updated_at = ?, default_agent = ?, trusts_pi_resources = ? WHERE id = ?;"
            )
            statement.bind(project.name, at: 1)
            statement.bind(project.path.path, at: 2)
            statement.bind(ISO8601Format.string(from: project.updatedAt), at: 3)
            statement.bind(agentToStore, at: 4)
            statement.bind(project.trustsPiResources ? 1 : 0, at: 5)
            statement.bind(project.id.uuidString.uppercased(), at: 6)
            try statement.step()
        }
    }

    /// Rewrites every position from the given order in one transaction.
    func updatePositions(_ orderedIDs: [UUID]) throws {
        try database.perform { connection in
            try connection.transaction {
                for (position, id) in orderedIDs.enumerated() {
                    let statement = try connection.prepare("UPDATE projects SET position = ? WHERE id = ?;")
                    statement.bind(position, at: 1)
                    statement.bind(id.uuidString.uppercased(), at: 2)
                    try statement.step()
                }
            }
        }
    }

    func delete(id: UUID) throws {
        try database.perform { connection in
            let statement = try connection.prepare("DELETE FROM projects WHERE id = ?;")
            statement.bind(id.uuidString.uppercased(), at: 1)
            try statement.step()
        }
    }
}

private enum ProjectRow {
    static func read(from statement: Statement) throws -> Project {
        guard let id = UUID(uuidString: try statement.column("id", at: 0)),
              let createdAt = ISO8601Format.date(from: try statement.column("created_at", at: 3)),
              let updatedAt = ISO8601Format.date(from: try statement.column("updated_at", at: 4)) else {
            throw DatabaseError.unexpectedNull(column: "id")
        }
        return Project(
            id: id,
            name: try statement.column("name", at: 1),
            path: URL(fileURLWithPath: try statement.column("path", at: 2)),
            defaultAgent: AgentKind(rawValue: try statement.column("default_agent", at: 5)) ?? .default,
            trustsPiResources: statement.columnInt(at: 6) != 0,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func bind(_ project: Project, to statement: Statement) {
        statement.bind(project.id.uuidString.uppercased(), at: 1)
        statement.bind(project.name, at: 2)
        statement.bind(project.path.path, at: 3)
        statement.bind(ISO8601Format.string(from: project.createdAt), at: 4)
        statement.bind(ISO8601Format.string(from: project.updatedAt), at: 5)
        statement.bind(project.defaultAgent.rawValue, at: 6)
        statement.bind(project.trustsPiResources ? 1 : 0, at: 7)
    }
}
