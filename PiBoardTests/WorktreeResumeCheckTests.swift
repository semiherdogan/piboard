import Foundation
import Testing
@testable import PiBoard

struct WorktreeResumeCheckTests {
    private static let branch = "piboard/resume-check"

    @Test func validWorktreeResolvesToItsPath() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try GitTestRepository.make()
        let root = try GitTestRepository.makeTempDirectory()
        defer {
            repository.remove()
            try? FileManager.default.removeItem(at: root)
        }
        let service = WorktreeService(rootDirectory: { root })
        let project = makeProject(path: repository.url)
        var task = makeTask(projectID: project.id)
        let created = try await service.create(for: task, project: project)
        task.worktreePath = created.path
        task.worktreeBranch = created.branch

        #expect(await WorktreeResumeCheck.run(task: task, project: project, worktrees: service) == .ok(created.path))
    }

    @Test func deletedWorktreeIsMissing() async throws {
        let projectDirectory = try GitTestRepository.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: projectDirectory) }
        let service = WorktreeService(rootDirectory: { projectDirectory })
        let project = makeProject(path: projectDirectory)
        var task = makeTask(projectID: project.id)
        task.worktreePath = projectDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        task.worktreeBranch = Self.branch

        #expect(await WorktreeResumeCheck.run(task: task, project: project, worktrees: service) == .missing)
    }

    @Test func plainDirectoryIsInvalid() async throws {
        let directory = try GitTestRepository.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = WorktreeService(rootDirectory: { directory })
        let project = makeProject(path: directory)
        var task = makeTask(projectID: project.id)
        task.worktreePath = directory
        task.worktreeBranch = Self.branch

        let result = await WorktreeResumeCheck.run(task: task, project: project, worktrees: service)

        guard case .invalid = result else {
            Issue.record("expected invalid, got \(result)")
            return
        }
    }

    private func makeProject(path: URL) -> Project {
        Project(id: UUID(), name: "Test", path: path, createdAt: Date(), updatedAt: Date())
    }

    private func makeTask(projectID: UUID) -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: projectID,
            title: "Resume check",
            prompt: "",
            status: .inProgress,
            position: 0,
            piSessionId: UUID(),
            runContext: .worktree,
            worktreePath: nil,
            worktreeBranch: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
