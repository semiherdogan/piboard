import Foundation

final class TaskRepository {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func fetchAll(projectID: UUID) throws -> [BoardTask] {
        try database.perform { connection in
            let statement = try connection.prepare(
                """
                SELECT id, project_id, title, prompt, status, position, pi_session_id,
                       run_context, worktree_path, worktree_branch, created_at, updated_at
                FROM tasks
                WHERE project_id = ?
                ORDER BY status, position;
                """
            )
            statement.bind(projectID.uuidString.uppercased(), at: 1)
            var rows: [BoardTask] = []
            while try statement.step() {
                rows.append(try TaskRow.read(from: statement))
            }
            return rows
        }
    }

    func insert(_ task: BoardTask) throws {
        try database.perform { connection in
            try Self.insert(task, on: connection)
        }
    }

    // Takes a connection already held by the caller so it can join that caller's transaction.
    static func insert(_ task: BoardTask, on connection: Connection) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO tasks (
                id, project_id, title, prompt, status, position, pi_session_id,
                run_context, worktree_path, worktree_branch, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        )
        TaskRow.bind(task, to: statement)
        try statement.step()
    }

    func update(_ task: BoardTask) throws {
        try database.perform { connection in
            let statement = try connection.prepare(
                """
                UPDATE tasks SET
                    title = ?, prompt = ?, status = ?, position = ?, pi_session_id = ?,
                    run_context = ?, worktree_path = ?, worktree_branch = ?, updated_at = ?
                WHERE id = ?;
                """
            )
            statement.bind(task.title, at: 1)
            statement.bind(task.prompt, at: 2)
            statement.bind(task.status.rawValue, at: 3)
            statement.bind(task.position, at: 4)
            statement.bind(task.piSessionId?.uuidString.uppercased(), at: 5)
            statement.bind(task.runContext?.rawValue, at: 6)
            statement.bind(task.worktreePath?.path, at: 7)
            statement.bind(task.worktreeBranch, at: 8)
            statement.bind(ISO8601Format.string(from: task.updatedAt), at: 9)
            statement.bind(task.id.uuidString.uppercased(), at: 10)
            try statement.step()
        }
    }

    func delete(id: UUID) throws {
        try database.perform { connection in
            let statement = try connection.prepare("DELETE FROM tasks WHERE id = ?;")
            statement.bind(id.uuidString.uppercased(), at: 1)
            try statement.step()
        }
    }

    /// Persists the status/position of every task in `ordered` as a single transaction.
    /// Only `movedTaskID` also writes `updated_at`, matching the in-memory reorder which
    /// bumps the timestamp solely for the task the user actually moved.
    func applyOrdering(_ ordered: [BoardTask], movedTaskID: BoardTask.ID) throws {
        try database.perform { connection in
            try connection.transaction {
                for task in ordered {
                    if task.id == movedTaskID {
                        let statement = try connection.prepare(
                            "UPDATE tasks SET status = ?, position = ?, updated_at = ? WHERE id = ?;"
                        )
                        statement.bind(task.status.rawValue, at: 1)
                        statement.bind(task.position, at: 2)
                        statement.bind(ISO8601Format.string(from: task.updatedAt), at: 3)
                        statement.bind(task.id.uuidString.uppercased(), at: 4)
                        try statement.step()
                    } else {
                        let statement = try connection.prepare(
                            "UPDATE tasks SET status = ?, position = ? WHERE id = ?;"
                        )
                        statement.bind(task.status.rawValue, at: 1)
                        statement.bind(task.position, at: 2)
                        statement.bind(task.id.uuidString.uppercased(), at: 3)
                        try statement.step()
                    }
                }
            }
        }
    }
}

private enum TaskRow {
    static func read(from statement: Statement) throws -> BoardTask {
        guard let id = UUID(uuidString: try statement.column("id", at: 0)),
              let projectId = UUID(uuidString: try statement.column("project_id", at: 1)),
              let status = TaskStatus(rawValue: try statement.column("status", at: 4)),
              let createdAt = ISO8601Format.date(from: try statement.column("created_at", at: 10)),
              let updatedAt = ISO8601Format.date(from: try statement.column("updated_at", at: 11)) else {
            throw DatabaseError.unexpectedNull(column: "id")
        }
        let piSessionId = statement.columnOptionalString(at: 6).flatMap(UUID.init(uuidString:))
        let runContext = statement.columnOptionalString(at: 7).flatMap(RunContext.init(rawValue:))
        let worktreePath = statement.columnOptionalString(at: 8).map(URL.init(fileURLWithPath:))
        return BoardTask(
            id: id,
            projectId: projectId,
            title: try statement.column("title", at: 2),
            prompt: try statement.column("prompt", at: 3),
            status: status,
            position: statement.columnInt(at: 5),
            piSessionId: piSessionId,
            runContext: runContext,
            worktreePath: worktreePath,
            worktreeBranch: statement.columnOptionalString(at: 9),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func bind(_ task: BoardTask, to statement: Statement) {
        statement.bind(task.id.uuidString.uppercased(), at: 1)
        statement.bind(task.projectId.uuidString.uppercased(), at: 2)
        statement.bind(task.title, at: 3)
        statement.bind(task.prompt, at: 4)
        statement.bind(task.status.rawValue, at: 5)
        statement.bind(task.position, at: 6)
        statement.bind(task.piSessionId?.uuidString.uppercased(), at: 7)
        statement.bind(task.runContext?.rawValue, at: 8)
        statement.bind(task.worktreePath?.path, at: 9)
        statement.bind(task.worktreeBranch, at: 10)
        statement.bind(ISO8601Format.string(from: task.createdAt), at: 11)
        statement.bind(ISO8601Format.string(from: task.updatedAt), at: 12)
    }
}
