import Foundation
import Testing
@testable import PiBoard

struct WorktreeServiceTests {
    @Test(arguments: [
        ("Fix login bug", "fix-login-bug"),
        ("Türkçe karakter: Çığ şöğüt İzmir", "turkce-karakter-cig-sogut-izmir"),
        ("  Add   multiple   spaces  ", "add-multiple-spaces"),
        ("Hello, world! (v2.0) -- done?", "hello-world-v2-0-done"),
        ("", ""),
        ("!!!", ""),
    ])
    func slugNormalizesTitle(title: String, expected: String) {
        #expect(WorktreeService.slug(title) == expected)
    }

    @Test func slugIsCappedWithoutTrailingSeparator() {
        let title = String(repeating: "abcdefghi ", count: 10)

        let slug = WorktreeService.slug(title)

        #expect(slug.count <= WorktreeService.slugMaxLength)
        #expect(slug == "abcdefghi-abcdefghi-abcdefghi-abcdefghi")
    }

    @Test func branchNameUsesPrefixShortIDAndSlug() throws {
        let taskID = try #require(UUID(uuidString: "ABCDEF12-3456-7890-ABCD-EF1234567890"))

        #expect(WorktreeService.branchName(taskID: taskID, title: "Fix Login") == "piboard/abcdef12-fix-login")
        #expect(WorktreeService.branchName(taskID: taskID, title: "???") == "piboard/abcdef12")
    }

    @Test func managedPathNestsProjectThenTask() {
        let root = URL(fileURLWithPath: "/tmp/worktrees", isDirectory: true)
        let projectID = UUID()
        let taskID = UUID()

        let path = WorktreeService.managedPath(root: root, projectID: projectID, taskID: taskID)

        #expect(path.path == "/tmp/worktrees/\(projectID.uuidString)/\(taskID.uuidString)")
    }

    @Test func createValidateReuseAndRemove() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try GitTestRepository.make()
        let root = try GitTestRepository.makeTempDirectory()
        defer {
            repository.remove()
            try? FileManager.default.removeItem(at: root)
        }
        let service = WorktreeService(rootDirectory: { root })
        let project = makeProject(path: repository.url)
        let task = makeTask(projectID: project.id, title: "Add worktree support")

        let created = try await service.create(for: task, project: project)

        #expect(created.path == WorktreeService.managedPath(root: root, projectID: project.id, taskID: task.id))
        #expect(created.branch == WorktreeService.branchName(taskID: task.id, title: task.title))
        #expect(await service.validate(created) == .valid)

        let reused = try await service.create(for: task, project: project)
        #expect(reused == created)

        try await service.remove(created, force: false)
        #expect(await service.validate(created) == .pathMissing)
    }

    @Test func createAfterRemoveReusesExistingBranch() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try GitTestRepository.make()
        let root = try GitTestRepository.makeTempDirectory()
        defer {
            repository.remove()
            try? FileManager.default.removeItem(at: root)
        }
        let service = WorktreeService(rootDirectory: { root })
        let project = makeProject(path: repository.url)
        let task = makeTask(projectID: project.id, title: "Rerun")

        let first = try await service.create(for: task, project: project)
        try await service.remove(first, force: true)
        let second = try await service.create(for: task, project: project)

        #expect(second == first)
        #expect(await service.validate(second) == .valid)
    }

    @Test func validateReportsBranchMismatch() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try GitTestRepository.make()
        let root = try GitTestRepository.makeTempDirectory()
        defer {
            repository.remove()
            try? FileManager.default.removeItem(at: root)
        }
        let service = WorktreeService(rootDirectory: { root })
        let project = makeProject(path: repository.url)
        let created = try await service.create(for: makeTask(projectID: project.id, title: "Branch"), project: project)

        let validation = await service.validate(WorktreeInfo(path: created.path, branch: "piboard/other"))

        #expect(validation == .branchMismatch(actual: created.branch))
    }

    @Test func validateReportsPlainDirectoryAsNotAWorktree() async throws {
        let directory = try GitTestRepository.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = WorktreeService(rootDirectory: { directory })

        #expect(await service.validate(WorktreeInfo(path: directory, branch: "piboard/x")) == .notAWorktree)
    }

    @Test func createOnNonRepositoryThrows() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let projectDirectory = try GitTestRepository.makeTempDirectory()
        let root = try GitTestRepository.makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: projectDirectory)
            try? FileManager.default.removeItem(at: root)
        }
        let service = WorktreeService(rootDirectory: { root })
        let project = makeProject(path: projectDirectory)

        await #expect(throws: GitServiceError.notARepository) {
            try await service.create(for: makeTask(projectID: project.id, title: "Nope"), project: project)
        }
    }

    private func makeProject(path: URL) -> Project {
        Project(id: UUID(), name: "Test", path: path, createdAt: Date(), updatedAt: Date())
    }

    private func makeTask(projectID: UUID, title: String) -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: projectID,
            title: title,
            prompt: "",
            status: .inProgress,
            position: 0,
            piSessionId: nil,
            runContext: .worktree,
            worktreePath: nil,
            worktreeBranch: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
