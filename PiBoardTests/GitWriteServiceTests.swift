import Foundation
import Testing
@testable import PiBoard

struct GitWriteServiceTests {
    private static let untrackedFileName = "untracked.txt"
    private static let commitMessage = "feat: change readme"

    private func fixture() throws -> GitTestRepository {
        let repository = try GitTestRepository.make()
        try repository.git("config", "user.name", "PiBoard Tests")
        try repository.git("config", "user.email", "tests@piboard.invalid")
        try repository.git("config", "commit.gpgsign", "false")
        return repository
    }

    @Test func stageAllThenCommitRecordsTheMessageAndClearsStatus() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try fixture()
        defer { repository.remove() }
        try repository.write("changed\n", to: GitTestRepository.trackedFileName)
        try repository.write("new\n", to: Self.untrackedFileName)
        let write = GitWriteService()

        try await write.stageAll(at: repository.url)
        try await write.commit(message: Self.commitMessage, at: repository.url)

        let status = try await GitService().status(at: repository.url)
        let log = try repository.output("log", "-1", "--format=%s").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(status.isEmpty)
        #expect(log == Self.commitMessage)
    }

    @Test func commitWithNothingStagedThrowsCommandFailed() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try fixture()
        defer { repository.remove() }
        let write = GitWriteService()

        await #expect(throws: GitServiceError.self) {
            try await write.commit(message: Self.commitMessage, at: repository.url)
        }
    }

    @Test func upstreamOnAFreshRepositoryIsNil() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try fixture()
        defer { repository.remove() }

        let upstream = try await GitWriteService().upstream(at: repository.url)

        #expect(upstream == nil)
    }

    @Test func diffAfterModifyingTheTrackedFileContainsTheChangeAndOmitsUntrackedFiles() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try fixture()
        defer { repository.remove() }
        try repository.write("changed\n", to: GitTestRepository.trackedFileName)
        try repository.write("new\n", to: Self.untrackedFileName)

        let diff = try await GitService().diff(at: repository.url)

        #expect(diff.contains("+changed"))
        #expect(!diff.contains(Self.untrackedFileName))
    }

    @Test func pushCommandArguments() {
        #expect(GitPushCommand.arguments(branch: "main", hasUpstream: true) == ["push"])
        #expect(GitPushCommand.arguments(branch: "main", hasUpstream: false) == ["push", "--set-upstream", "origin", "main"])
    }

    @Test func discardRestoresAModifiedFile() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try fixture()
        defer { repository.remove() }
        try repository.write("changed\n", to: GitTestRepository.trackedFileName)

        try await GitWriteService().discard(GitChange(status: " M", path: GitTestRepository.trackedFileName), at: repository.url)

        let status = try await GitService().status(at: repository.url)
        let contents = try String(contentsOf: repository.url.appendingPathComponent(GitTestRepository.trackedFileName), encoding: .utf8)
        #expect(status.isEmpty)
        #expect(contents == "hello\n")
    }

    @Test func discardDeletesAnUntrackedFile() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try fixture()
        defer { repository.remove() }
        try repository.write("new\n", to: Self.untrackedFileName)

        try await GitWriteService().discard(GitChange(status: "??", path: Self.untrackedFileName), at: repository.url)

        let status = try await GitService().status(at: repository.url)
        #expect(status.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: repository.url.appendingPathComponent(Self.untrackedFileName).path))
    }

    @Test func discardDeletesAnUntrackedDirectory() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try fixture()
        defer { repository.remove() }
        let directory = repository.url.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("inner\n".utf8).write(to: directory.appendingPathComponent("inner.txt"))

        try await GitWriteService().discard(GitChange(status: "??", path: "dir/"), at: repository.url)

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func discardRemovesAStagedNewFile() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try fixture()
        defer { repository.remove() }
        try repository.write("added\n", to: "added.txt")
        try repository.git("add", "added.txt")
        let staged = try await GitService().status(at: repository.url)
        #expect(staged.first?.status == "A ")

        try await GitWriteService().discard(GitChange(status: "A ", path: "added.txt"), at: repository.url)

        let status = try await GitService().status(at: repository.url)
        #expect(status.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: repository.url.appendingPathComponent("added.txt").path))
    }

    @Test func discardRestoresAStagedModification() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try fixture()
        defer { repository.remove() }
        try repository.write("changed\n", to: GitTestRepository.trackedFileName)
        try repository.git("add", GitTestRepository.trackedFileName)
        let staged = try await GitService().status(at: repository.url)
        #expect(staged.first?.status == "M ")

        try await GitWriteService().discard(GitChange(status: "M ", path: GitTestRepository.trackedFileName), at: repository.url)

        let status = try await GitService().status(at: repository.url)
        let contents = try String(contentsOf: repository.url.appendingPathComponent(GitTestRepository.trackedFileName), encoding: .utf8)
        #expect(status.isEmpty)
        #expect(contents == "hello\n")
    }

    @Test func discardRefusesARename() async throws {
        try #require(GitTestRepository.isGitAvailable)
        let repository = try fixture()
        defer { repository.remove() }

        await #expect(throws: GitWriteError.cannotDiscard(.renamed)) {
            try await GitWriteService().discard(GitChange(status: "R ", path: "x"), at: repository.url)
        }
    }
}
