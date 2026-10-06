import Foundation
import Testing
@testable import PiBoard

struct TaskRepositoryTests {
    private func makeRepositories() throws -> (Database, ProjectRepository, TaskRepository) {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let projectRepository = ProjectRepository(database: database)
        let taskRepository = TaskRepository(database: database)
        let project = Project(id: UUID(), name: "My App", path: URL(fileURLWithPath: "/tmp/my-app"), createdAt: Date(), updatedAt: Date())
        try projectRepository.insert(project)
        return (database, projectRepository, taskRepository)
    }

    private func makeTask(
        projectId: UUID,
        status: TaskStatus = .backlog,
        position: Int = 0,
        piSessionId: UUID? = nil,
        runContext: RunContext? = nil,
        worktreePath: URL? = nil,
        worktreeBranch: String? = nil
    ) -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: projectId,
            title: "Task",
            prompt: "Prompt",
            status: status,
            position: position,
            piSessionId: piSessionId,
            runContext: runContext,
            worktreePath: worktreePath,
            worktreeBranch: worktreeBranch,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @Test func insertAndFetchRoundTripsNilOptionalFields() throws {
        let (_, projectRepository, taskRepository) = try makeRepositories()
        let project = try projectRepository.fetchAll()[0]
        let task = makeTask(projectId: project.id)

        try taskRepository.insert(task)
        let fetched = try taskRepository.fetchAll(projectID: project.id)

        #expect(fetched.count == 1)
        #expect(fetched[0].piSessionId == nil)
        #expect(fetched[0].runContext == nil)
        #expect(fetched[0].worktreePath == nil)
        #expect(fetched[0].worktreeBranch == nil)
    }

    @Test func insertAndFetchRoundTripsNonNilOptionalFields() throws {
        let (_, projectRepository, taskRepository) = try makeRepositories()
        let project = try projectRepository.fetchAll()[0]
        let task = makeTask(
            projectId: project.id,
            status: .inProgress,
            piSessionId: UUID(),
            runContext: .worktree,
            worktreePath: URL(fileURLWithPath: "/tmp/my-app/.piboard/worktrees/fix"),
            worktreeBranch: "piboard/fix"
        )

        try taskRepository.insert(task)
        let fetched = try taskRepository.fetchAll(projectID: project.id)

        #expect(fetched[0].piSessionId == task.piSessionId)
        #expect(fetched[0].runContext == task.runContext)
        #expect(fetched[0].worktreePath == task.worktreePath)
        #expect(fetched[0].worktreeBranch == task.worktreeBranch)
    }

    @Test func statusCheckConstraintRejectsAnInvalidRawValue() throws {
        let (database, projectRepository, _) = try makeRepositories()
        let project = try projectRepository.fetchAll()[0]

        #expect(throws: DatabaseError.self) {
            try database.perform { connection in
                let statement = try connection.prepare(
                    """
                    INSERT INTO tasks (id, project_id, title, prompt, status, position, created_at, updated_at)
                    VALUES (?, ?, 'Bad', '', 'bogus', 0, '2024-01-01T00:00:00.000Z', '2024-01-01T00:00:00.000Z');
                    """
                )
                statement.bind(UUID().uuidString, at: 1)
                statement.bind(project.id.uuidString, at: 2)
                try statement.step()
            }
        }
    }

    @Test func applyOrderingPersistsPositions() throws {
        let (_, projectRepository, taskRepository) = try makeRepositories()
        let project = try projectRepository.fetchAll()[0]
        let a = makeTask(projectId: project.id, status: .backlog, position: 0)
        let b = makeTask(projectId: project.id, status: .backlog, position: 1)
        try taskRepository.insert(a)
        try taskRepository.insert(b)

        var reordered = [a, b]
        reordered[0].position = 1
        reordered[1].position = 0

        try taskRepository.applyOrdering(reordered, movedTaskID: b.id)

        let fetched = try taskRepository.fetchAll(projectID: project.id)
        #expect(fetched.first { $0.id == a.id }?.position == 1)
        #expect(fetched.first { $0.id == b.id }?.position == 0)
    }

    /// `applyOrdering` relies on `Connection.transaction` rolling back every statement in
    /// the batch when one fails. `BoardTask.status` can only ever hold a valid `TaskStatus`
    /// raw value, so a genuine CHECK violation cannot be produced through the repository's
    /// typed API; this exercises the same transaction path with a raw, deliberately invalid
    /// second statement to prove the first row's write does not survive.
    @Test func transactionRollsBackEarlierWritesWhenALaterStatementFails() throws {
        let (database, projectRepository, taskRepository) = try makeRepositories()
        let project = try projectRepository.fetchAll()[0]
        let a = makeTask(projectId: project.id, status: .backlog, position: 0)
        let b = makeTask(projectId: project.id, status: .backlog, position: 1)
        try taskRepository.insert(a)
        try taskRepository.insert(b)

        #expect(throws: DatabaseError.self) {
            try database.perform { connection in
                try connection.transaction {
                    let updateA = try connection.prepare("UPDATE tasks SET position = 5 WHERE id = ?;")
                    updateA.bind(a.id.uuidString.uppercased(), at: 1)
                    try updateA.step()

                    let updateB = try connection.prepare("UPDATE tasks SET status = 'bogus' WHERE id = ?;")
                    updateB.bind(b.id.uuidString.uppercased(), at: 1)
                    try updateB.step()
                }
            }
        }

        let fetched = try taskRepository.fetchAll(projectID: project.id)
        #expect(fetched.first { $0.id == a.id }?.position == 0)
    }
}
