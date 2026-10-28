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

    @Test func recentSubjectsReturnsTheNewestCommitsFirst() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try GitTestRepository.make()
        defer { repository.remove() }

        let initial = try await service.recentSubjects(limit: 5, at: repository.url)
        #expect(initial == ["initial"])

        try repository.write("second\n", to: "second.txt")
        try repository.git("add", "second.txt")
        try repository.commit("second")
        try repository.write("third\n", to: "third.txt")
        try repository.git("add", "third.txt")
        try repository.commit("third")

        let newest = try await service.recentSubjects(limit: 2, at: repository.url)
        #expect(newest == ["third", "second"])
    }

    @Test func branchSyncWithoutUpstreamIsUnpublished() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try GitTestRepository.make()
        defer { repository.remove() }

        let sync = try await service.branchSync(at: repository.url)

        #expect(sync == BranchSync(upstream: nil, ahead: 0, behind: 0))
        #expect(sync?.hasUnpushedCommits == true)
    }

    @Test func branchSyncCountsCommitsAheadOfTheUpstream() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try GitTestRepository.make()
        let remote = try GitTestRepository.makeTempDirectory()
        defer {
            repository.remove()
            try? FileManager.default.removeItem(at: remote)
        }
        try repository.git("clone", "--bare", "-q", ".", remote.path)
        try repository.git("remote", "add", GitArguments.defaultRemoteName, remote.path)
        try repository.git("push", "-q", "-u", GitArguments.defaultRemoteName, GitTestRepository.initialBranch)
        try repository.write("more\n", to: "more.txt")
        try repository.git("add", "more.txt")
        try repository.commit("more")

        let sync = try await service.branchSync(at: repository.url)

        #expect(sync?.upstream == "\(GitArguments.defaultRemoteName)/\(GitTestRepository.initialBranch)")
        #expect(sync?.ahead == 1)
        #expect(sync?.behind == 0)
        #expect(sync?.hasUnpushedCommits == true)
    }

    @Test func defaultBranchComesFromTheRemoteHead() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try GitTestRepository.make()
        let remote = try GitTestRepository.makeTempDirectory()
        defer {
            repository.remove()
            try? FileManager.default.removeItem(at: remote)
        }
        try repository.git("clone", "--bare", "-q", ".", remote.path)
        try repository.git("remote", "add", GitArguments.defaultRemoteName, remote.path)
        try repository.git("push", "-q", "-u", GitArguments.defaultRemoteName, GitTestRepository.initialBranch)

        let withoutHead = try await service.defaultBranch(at: repository.url)
        #expect(withoutHead == nil)

        try repository.git("remote", "set-head", GitArguments.defaultRemoteName, GitTestRepository.initialBranch)

        let withHead = try await service.defaultBranch(at: repository.url)
        #expect(withHead == GitTestRepository.initialBranch)
    }
}
