import Foundation
import Testing
@testable import PiBoard

struct ProjectRepositoryTests {
    private func makeRepository() throws -> (ProjectRepository, TaskRepository) {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        return (ProjectRepository(database: database), TaskRepository(database: database))
    }

    private static let futureAgent = "future-agent"

    private func storeRawDefaultAgent(_ raw: String, for project: Project, in database: Database) throws {
        try database.perform { connection in
            let statement = try connection.prepare("UPDATE projects SET default_agent = ? WHERE id = ?;")
            statement.bind(raw, at: 1)
            statement.bind(project.id.uuidString.uppercased(), at: 2)
            try statement.step()
        }
    }

    private func rawDefaultAgent(of project: Project, in database: Database) throws -> String? {
        try database.perform { connection in
            let statement = try connection.prepare("SELECT default_agent FROM projects WHERE id = ?;")
            statement.bind(project.id.uuidString.uppercased(), at: 1)
            return try statement.step() ? try statement.column("default_agent", at: 0) : nil
        }
    }

    private func makeProject() -> Project {
        Project(
            id: UUID(),
            name: "My App",
            path: URL(fileURLWithPath: "/tmp/my-app"),
            defaultAgent: .default,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @Test func insertAndFetchRoundTripsAllFields() throws {
        let (repository, _) = try makeRepository()
        let project = makeProject()

        try repository.insert(project)
        let fetched = try repository.fetchAll()

        #expect(fetched.count == 1)
        #expect(fetched[0].id == project.id)
        #expect(fetched[0].name == project.name)
        #expect(fetched[0].path == project.path)
        #expect(fetched[0].defaultAgent == project.defaultAgent)
        #expect(millis(fetched[0].createdAt) == millis(project.createdAt))
        #expect(millis(fetched[0].updatedAt) == millis(project.updatedAt))
    }

    @Test func fetchAllOrdersByCreatedAt() throws {
        let (repository, _) = try makeRepository()
        let older = Project(id: UUID(), name: "Older", path: URL(fileURLWithPath: "/tmp/older"), defaultAgent: .default, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date())
        let newer = Project(id: UUID(), name: "Newer", path: URL(fileURLWithPath: "/tmp/newer"), defaultAgent: .default, createdAt: Date(timeIntervalSince1970: 1000), updatedAt: Date())

        try repository.insert(newer)
        try repository.insert(older)

        let fetched = try repository.fetchAll()
        #expect(fetched.map(\.id) == [older.id, newer.id])
    }

    @Test func updateChangesNameAndPath() throws {
        let (repository, _) = try makeRepository()
        var project = makeProject()
        try repository.insert(project)

        project.name = "Renamed"
        project.path = URL(fileURLWithPath: "/tmp/renamed")
        project.defaultAgent = .pi
        project.updatedAt = Date()
        try repository.update(project)

        let fetched = try repository.fetchAll()
        #expect(fetched[0].name == "Renamed")
        #expect(fetched[0].path == URL(fileURLWithPath: "/tmp/renamed"))
    }

    @Test func unknownStoredDefaultAgentSurvivesARename() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let repository = ProjectRepository(database: database)
        let project = makeProject()
        try repository.insert(project)
        try storeRawDefaultAgent(Self.futureAgent, for: project, in: database)

        var fetched = try repository.fetchAll()[0]
        #expect(fetched.defaultAgent == .default)
        fetched.name = "Renamed"
        try repository.update(fetched)

        #expect(try rawDefaultAgent(of: project, in: database) == Self.futureAgent)
    }

    @Test func explicitNonDefaultAgentOverwritesAnUnknownStoredValue() throws {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        let repository = ProjectRepository(database: database)
        let project = makeProject()
        try repository.insert(project)
        try storeRawDefaultAgent(Self.futureAgent, for: project, in: database)

        var fetched = try repository.fetchAll()[0]
        fetched.defaultAgent = .claudeCode
        try repository.update(fetched)

        #expect(try rawDefaultAgent(of: project, in: database) == AgentKind.claudeCode.rawValue)
    }

    @Test func deletingProjectCascadesTasksViaForeignKeys() throws {
        let (projectRepository, taskRepository) = try makeRepository()
        let project = makeProject()
        try projectRepository.insert(project)

        let task = BoardTask(
            id: UUID(),
            projectId: project.id,
            agent: .default,
            title: "Task",
            prompt: "",
            status: .backlog,
            position: 0,
            sessionID: nil,
            runContext: nil,
            worktreePath: nil,
            worktreeBranch: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try taskRepository.insert(task)

        try projectRepository.delete(id: project.id)

        #expect(try taskRepository.fetchAll(projectID: project.id).isEmpty)
    }

    private func millis(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }
}
