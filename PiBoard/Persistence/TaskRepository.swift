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
                       run_context, worktree_path, worktree_branch, created_at, updated_at, agent,
                       previous_agent, previous_session_id
                FROM tasks
                WHERE project_id = ?
                ORDER BY status, position;
                """
            )
            statement.bind(projectID.uuidString.uppercased(), at: 1)
            var rows: [BoardTask] = []
            while try statement.step() {
                if let task = try TaskRow.read(from: statement) {
                    rows.append(task)
                }
            }
            return rows
        }
    }

    /// Rows `fetchAll` leaves out because they name an agent this build does not know.
    func unsupportedAgentTaskCount(projectID: UUID? = nil) throws -> Int {
        try database.perform { connection in
            let statement: Statement
            if let projectID {
                statement = try connection.prepare("SELECT agent, previous_agent FROM tasks WHERE project_id = ?;")
                statement.bind(projectID.uuidString.uppercased(), at: 1)
            } else {
                statement = try connection.prepare("SELECT agent, previous_agent FROM tasks;")
            }
            var count = 0
            while try statement.step() {
                let agent: String = try statement.column("agent", at: 0)
                if !TaskRow.isSupported(agent: agent, previousAgent: statement.columnOptionalString(at: 1)) {
                    count += 1
                }
            }
            return count
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
                run_context, worktree_path, worktree_branch, created_at, updated_at, agent,
                previous_agent, previous_session_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
                    run_context = ?, worktree_path = ?, worktree_branch = ?, updated_at = ?, agent = ?,
                    previous_agent = ?, previous_session_id = ?
                WHERE id = ?;
                """
            )
            statement.bind(task.title, at: 1)
            statement.bind(task.prompt, at: 2)
            statement.bind(task.status.rawValue, at: 3)
            statement.bind(task.position, at: 4)
            statement.bind(task.sessionID, at: 5)
            statement.bind(task.runContext?.rawValue, at: 6)
            statement.bind(task.worktreePath?.path, at: 7)
            statement.bind(task.worktreeBranch, at: 8)
            statement.bind(ISO8601Format.string(from: task.updatedAt), at: 9)
            statement.bind(task.agent.rawValue, at: 10)
            statement.bind(task.previousAgent?.rawValue, at: 11)
            statement.bind(task.previousSessionID, at: 12)
            statement.bind(task.id.uuidString.uppercased(), at: 13)
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
    // An unknown agent must never be mapped to a known one, Pi would resume or delete another tool's session.
    static func isSupported(agent: String, previousAgent: String?) -> Bool {
        guard AgentKind(rawValue: agent) != nil else { return false }
        guard let previousAgent else { return true }
        return AgentKind(rawValue: previousAgent) != nil
    }

    static func read(from statement: Statement) throws -> BoardTask? {
        let rawAgent: String = try statement.column("agent", at: 12)
        let rawPreviousAgent = statement.columnOptionalString(at: 13)
        guard isSupported(agent: rawAgent, previousAgent: rawPreviousAgent),
              let agent = AgentKind(rawValue: rawAgent) else {
            return nil
        }
        guard let id = UUID(uuidString: try statement.column("id", at: 0)),
              let projectId = UUID(uuidString: try statement.column("project_id", at: 1)),
              let status = TaskStatus(rawValue: try statement.column("status", at: 4)),
              let createdAt = ISO8601Format.date(from: try statement.column("created_at", at: 10)),
              let updatedAt = ISO8601Format.date(from: try statement.column("updated_at", at: 11)) else {
            throw DatabaseError.unexpectedNull(column: "id")
        }
        let previousAgent = rawPreviousAgent.flatMap(AgentKind.init(rawValue:))
        let runContext = statement.columnOptionalString(at: 7).flatMap(RunContext.init(rawValue:))
        let worktreePath = statement.columnOptionalString(at: 8).map(URL.init(fileURLWithPath:))
        return BoardTask(
            id: id,
            projectId: projectId,
            agent: agent,
            title: try statement.column("title", at: 2),
            prompt: try statement.column("prompt", at: 3),
            status: status,
            position: statement.columnInt(at: 5),
            sessionID: statement.columnOptionalString(at: 6),
            previousAgent: previousAgent,
            previousSessionID: statement.columnOptionalString(at: 14),
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
        statement.bind(task.sessionID, at: 7)
        statement.bind(task.runContext?.rawValue, at: 8)
        statement.bind(task.worktreePath?.path, at: 9)
        statement.bind(task.worktreeBranch, at: 10)
        statement.bind(ISO8601Format.string(from: task.createdAt), at: 11)
        statement.bind(ISO8601Format.string(from: task.updatedAt), at: 12)
        statement.bind(task.agent.rawValue, at: 13)
        statement.bind(task.previousAgent?.rawValue, at: 14)
        statement.bind(task.previousSessionID, at: 15)
    }
}
