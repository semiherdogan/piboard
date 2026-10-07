import Foundation
import Testing
@testable import PiBoard

struct FakeGitService: GitServicing {
    var repositoryInfoResult: Result<RepositoryInfo, any Error> = .success(.notARepository)
    var statusResult: Result<[GitChange], any Error> = .success([])
    var remoteBrowseURLResult: Result<URL?, any Error> = .success(nil)
    /// Counts reads so the tests can tell a cached remote from a re-read one.
    var remoteReads = CallCount()

    func remoteBrowseURL(at path: URL) async throws -> URL? {
        remoteReads.increment()
        return try remoteBrowseURLResult.get()
    }

    func repositoryInfo(at path: URL) async throws -> RepositoryInfo {
        try repositoryInfoResult.get()
    }

    func status(at path: URL) async throws -> [GitChange] {
        try statusResult.get()
    }

    func currentBranch(at path: URL) async throws -> String? {
        try repositoryInfoResult.get().headBranch
    }
}

final class CallCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}

struct GitRemoteSelectionTests {
    private let fetchLine = "origin\tgit@github.com:owner/repo.git (fetch)"

    @Test func originWinsOverOtherRemotes() {
        let output = """
        upstream\tgit@github.com:upstream/repo.git (fetch)
        upstream\tgit@github.com:upstream/repo.git (push)
        \(fetchLine)
        origin\tgit@github.com:owner/repo.git (push)
        """
        #expect(GitService.preferredRemote(output) == "git@github.com:owner/repo.git")
    }

    // A clone whose remote was renamed still has somewhere to browse.
    @Test func theFirstRemoteIsUsedWhenThereIsNoOrigin() {
        let output = """
        fork\tgit@github.com:me/repo.git (fetch)
        fork\tgit@github.com:me/repo.git (push)
        """
        #expect(GitService.preferredRemote(output) == "git@github.com:me/repo.git")
    }

    @Test func aPushOnlyRemoteIsSkipped() {
        let output = "backup\tgit@github.com:me/backup.git (push)\n\(fetchLine)"
        #expect(GitService.preferredRemote(output) == "git@github.com:owner/repo.git")
    }

    @Test func aRepositoryWithoutRemotesSelectsNothing() {
        #expect(GitService.preferredRemote("") == nil)
        #expect(GitService.preferredRemote("garbage without a tab") == nil)
    }
}

@MainActor
struct ProjectGitStatusModelTests {
    private static let path = URL(fileURLWithPath: "/tmp/project")
    private static let branch = "main"
    private static let repository = RepositoryInfo(isRepository: true, topLevel: path, headBranch: branch)

    private func refreshed(_ git: FakeGitService) async -> ProjectGitStatusModel {
        let model = ProjectGitStatusModel(git: git)
        #expect(model.state == .idle)
        model.refresh(path: Self.path)
        #expect(model.state == .loading)
        await model.refreshTask?.value
        return model
    }

    @Test func notRepository() async {
        let model = await refreshed(FakeGitService())
        #expect(model.state == .notRepository)
    }

    @Test func cleanRepository() async {
        let model = await refreshed(FakeGitService(repositoryInfoResult: .success(Self.repository)))
        #expect(model.state == .ready(branch: Self.branch, changeCount: 0))
    }

    @Test func remoteIsLoadedAlongsideTheStatus() async {
        let remote = URL(string: "https://github.com/owner/repo")!
        let model = await refreshed(FakeGitService(
            repositoryInfoResult: .success(Self.repository),
            remoteBrowseURLResult: .success(remote)
        ))
        #expect(model.remoteURL == remote)
    }

    // A repository with no remote, or a git call that fails only for the remote, must still show
    // its status rather than falling into the failed state.
    @Test func aMissingRemoteDoesNotFailTheRefresh() async {
        for remoteResult in [Result<URL?, any Error>.success(nil), .failure(GitServiceError.timedOut)] {
            let model = await refreshed(FakeGitService(
                repositoryInfoResult: .success(Self.repository),
                remoteBrowseURLResult: remoteResult
            ))
            #expect(model.state == .ready(branch: Self.branch, changeCount: 0))
            #expect(model.remoteURL == nil)
        }
    }

    @Test func aFolderThatIsNotARepositoryHasNoRemote() async {
        let model = await refreshed(FakeGitService(
            remoteBrowseURLResult: .success(URL(string: "https://github.com/owner/repo")!)
        ))
        #expect(model.remoteURL == nil)
    }

    // MARK: Caching the remote

    private func readyWithRemote() -> FakeGitService {
        FakeGitService(
            repositoryInfoResult: .success(Self.repository),
            remoteBrowseURLResult: .success(URL(string: "https://github.com/owner/repo")!)
        )
    }

    @Test func automaticRefreshesReuseTheRemoteInsteadOfRereadingIt() async {
        let git = readyWithRemote()
        let model = await refreshed(git)
        #expect(git.remoteReads.value == 1)

        for _ in 0..<3 {
            model.refresh(path: Self.path)
            await model.refreshTask?.value
        }
        #expect(git.remoteReads.value == 1)
        #expect(model.remoteURL != nil)
    }

    @Test func theRefreshButtonRereadsTheRemote() async {
        let git = readyWithRemote()
        let model = await refreshed(git)

        model.refresh(path: Self.path, reloadRemote: true)
        await model.refreshTask?.value
        #expect(git.remoteReads.value == 2)
    }

    @Test func switchingProjectsReadsTheNewRemote() async {
        let git = readyWithRemote()
        let model = await refreshed(git)

        model.refresh(path: URL(fileURLWithPath: "/tmp/other"))
        await model.refreshTask?.value
        #expect(git.remoteReads.value == 2)
    }

    // Nothing is cached after a failed read, so the next refresh tries again on its own.
    @Test func aFailedReadIsRetriedWithoutPressingRefresh() async {
        let git = FakeGitService(
            repositoryInfoResult: .success(Self.repository),
            remoteBrowseURLResult: .failure(GitServiceError.timedOut)
        )
        let model = await refreshed(git)
        #expect(git.remoteReads.value == 1)

        model.refresh(path: Self.path)
        await model.refreshTask?.value
        #expect(git.remoteReads.value == 2)
    }

    @Test func dirtyRepository() async {
        let changes = ["a.swift", "b.swift", "c.swift"].map { GitChange(status: " M", path: $0) }
        let model = await refreshed(FakeGitService(
            repositoryInfoResult: .success(Self.repository),
            statusResult: .success(changes)
        ))
        #expect(model.state == .ready(branch: Self.branch, changeCount: changes.count))
    }

    @Test func failure() async {
        let error = GitServiceError.timedOut
        let model = await refreshed(FakeGitService(
            repositoryInfoResult: .success(Self.repository),
            statusResult: .failure(error)
        ))
        #expect(model.state == .failed(error.localizedDescription))
    }

    @Test func refreshOfLoadedPathKeepsPreviousResult() async {
        let model = await refreshed(FakeGitService(repositoryInfoResult: .success(Self.repository)))
        model.refresh(path: Self.path)
        #expect(model.state == .ready(branch: Self.branch, changeCount: 0))
        await model.refreshTask?.value
    }
}
