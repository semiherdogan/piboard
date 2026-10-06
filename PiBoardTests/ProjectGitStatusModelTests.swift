import Foundation
import Testing
@testable import PiBoard

struct FakeGitService: GitServicing {
    var repositoryInfoResult: Result<RepositoryInfo, any Error> = .success(.notARepository)
    var statusResult: Result<[GitChange], any Error> = .success([])

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
