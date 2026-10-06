import Foundation
import Testing
@testable import PiBoard

struct ProjectRepositoryTests {
    private func makeRepository() throws -> (ProjectRepository, TaskRepository) {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        return (ProjectRepository(database: database), TaskRepository(database: database))
    }

    private func makeProject() -> Project {
        Project(
            id: UUID(),
            name: "My App",
            path: URL(fileURLWithPath: "/tmp/my-app"),
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
        #expect(millis(fetched[0].createdAt) == millis(project.createdAt))
        #expect(millis(fetched[0].updatedAt) == millis(project.updatedAt))
    }

    @Test func fetchAllOrdersByCreatedAt() throws {
        let (repository, _) = try makeRepository()
        let older = Project(id: UUID(), name: "Older", path: URL(fileURLWithPath: "/tmp/older"), createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date())
        let newer = Project(id: UUID(), name: "Newer", path: URL(fileURLWithPath: "/tmp/newer"), createdAt: Date(timeIntervalSince1970: 1000), updatedAt: Date())

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
        project.updatedAt = Date()
        try repository.update(project)

        let fetched = try repository.fetchAll()
        #expect(fetched[0].name == "Renamed")
        #expect(fetched[0].path == URL(fileURLWithPath: "/tmp/renamed"))
    }

    @Test func deletingProjectCascadesTasksViaForeignKeys() throws {
        let (projectRepository, taskRepository) = try makeRepository()
        let project = makeProject()
        try projectRepository.insert(project)

        let task = BoardTask(
            id: UUID(),
            projectId: project.id,
            title: "Task",
            prompt: "",
            status: .backlog,
            position: 0,
            piSessionId: nil,
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
