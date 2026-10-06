import Foundation

final class ProjectRepository {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func fetchAll() throws -> [Project] {
        try database.perform { connection in
            let statement = try connection.prepare(
                "SELECT id, name, path, created_at, updated_at FROM projects ORDER BY created_at;"
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
            let statement = try connection.prepare(
                "INSERT INTO projects (id, name, path, created_at, updated_at) VALUES (?, ?, ?, ?, ?);"
            )
            ProjectRow.bind(project, to: statement)
            try statement.step()
        }
    }

    func update(_ project: Project) throws {
        try database.perform { connection in
            let statement = try connection.prepare(
                "UPDATE projects SET name = ?, path = ?, updated_at = ? WHERE id = ?;"
            )
            statement.bind(project.name, at: 1)
            statement.bind(project.path.path, at: 2)
            statement.bind(ISO8601Format.string(from: project.updatedAt), at: 3)
            statement.bind(project.id.uuidString.uppercased(), at: 4)
            try statement.step()
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
    }
}
