import Foundation
import Testing
@testable import PiBoard

struct GitServiceTests {
    private let service = GitService()

    @Test func nonRepositoryDirectoryIsNotARepository() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let directory = try GitTestRepository.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let info = try await service.repositoryInfo(at: directory)

        #expect(info == .notARepository)
    }

    @Test func freshRepositoryReportsBranchTopLevelAndCleanStatus() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try GitTestRepository.make()
        defer { repository.remove() }

        let info = try await service.repositoryInfo(at: repository.url)
        let changes = try await service.status(at: repository.url)

        #expect(info.isRepository)
        #expect(info.headBranch == GitTestRepository.initialBranch)
        #expect(info.topLevel.map(ProjectPathService.canonicalize) == repository.url)
        #expect(changes.isEmpty)
    }

    @Test func statusReportsModifiedAndUntrackedFiles() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try GitTestRepository.make()
        defer { repository.remove() }
        try repository.write("changed\n", to: GitTestRepository.trackedFileName)
        try repository.write("new\n", to: "untracked.txt")

        let changes = try await service.status(at: repository.url)

        #expect(changes.contains(GitChange(status: " M", path: GitTestRepository.trackedFileName)))
        #expect(changes.contains(GitChange(status: "??", path: "untracked.txt")))
        #expect(changes.count == 2)
    }

    @Test func statusOnNonRepositoryThrowsNotARepository() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let directory = try GitTestRepository.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        await #expect(throws: GitServiceError.notARepository) {
            try await service.status(at: directory)
        }
    }

    @Test func parsePorcelainReadsNulSeparatedEntries() {
        let data = Data(" M Sources/App.swift\0?? notes with spaces.txt\0A  added.txt\0".utf8)

        let changes = GitService.parsePorcelain(data)

        #expect(changes == [
            GitChange(status: " M", path: "Sources/App.swift"),
            GitChange(status: "??", path: "notes with spaces.txt"),
            GitChange(status: "A ", path: "added.txt"),
        ])
    }

    @Test func parsePorcelainSkipsOriginalPathOfRename() {
        // `-z` renames are "XY new\0old\0", not "old -> new".
        let data = Data("R  new.txt\0old.txt\0 D gone.txt\0".utf8)

        let changes = GitService.parsePorcelain(data)

        #expect(changes == [
            GitChange(status: "R ", path: "new.txt"),
            GitChange(status: " D", path: "gone.txt"),
        ])
    }

    @Test func parsePorcelainOfEmptyOutputIsEmpty() {
        #expect(GitService.parsePorcelain(Data()).isEmpty)
    }
}
