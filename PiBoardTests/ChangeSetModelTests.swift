import Foundation
import Testing
@testable import PiBoard

@MainActor
struct ChangeSetModelTests {
    private static let path = URL(fileURLWithPath: "/tmp/project")
    private static let stagedChanges = [GitChange(status: "M ", path: "README.md")]
    private static let diffText = "diff --git a/README.md b/README.md\n--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-a\n+b\n"

    private func makeModel(
        info: RepositoryInfo = RepositoryInfo(isRepository: true, topLevel: path, headBranch: "main"),
        changes: [GitChange] = [GitChange(status: " M", path: "README.md")],
        writer: FakeGitWriter = FakeGitWriter()
    ) -> ChangeSetModel {
        let git = FakeGitService(
            repositoryInfoResult: .success(info),
            statusResult: .success(changes),
            diffResult: .success(Self.diffText)
        )
        return ChangeSetModel(git: git, writer: writer)
    }

    private func loaded(_ model: ChangeSetModel) async {
        model.load(path: Self.path)
        await model.actionTask?.value
    }

    @Test func loadFillsTheChangeSet() async throws {
        let model = makeModel()
        model.load(path: Self.path)

        #expect(model.phase == .loading)
        #expect(model.changeSet == nil)

        await model.actionTask?.value

        #expect(model.phase == .ready)
        #expect(model.changeSet?.changes.count == 1)
        #expect(model.changeSet?.branch == "main")
        #expect(model.changeSet?.diff.files.map(\.path) == ["README.md"])
        #expect(model.lastError == nil)
    }

    @Test func loadOnANonRepositoryReportsIt() async throws {
        let model = makeModel(info: .notARepository)
        await loaded(model)

        #expect(model.changeSet == nil)
        #expect(model.lastError == ChangeSetModel.notARepositoryMessage)
        #expect(model.phase == .ready)
    }

    @Test func reloadKeepsTheListWhileReading() async throws {
        let model = makeModel()
        await loaded(model)

        model.reload()

        #expect(model.phase == .loading)
        #expect(model.changeSet != nil)

        await model.actionTask?.value

        #expect(model.phase == .ready)
    }

    @Test func resetClearsEverything() async throws {
        let model = makeModel()
        await loaded(model)

        model.reset()

        #expect(model.changeSet == nil)
        #expect(model.path == nil)
        #expect(model.phase == .idle)
    }

    @Test func toggleStagedOnAnUnstagedFileRunsAdd() async throws {
        let writer = FakeGitWriter()
        let model = makeModel(writer: writer)
        await loaded(model)

        model.toggleStaged(GitChange(status: " M", path: "README.md"))
        await model.actionTask?.value

        #expect(writer.staged == ["README.md"])
        #expect(model.phase == .ready)
    }

    @Test func toggleStagedOnAStagedFileRunsRestore() async throws {
        let writer = FakeGitWriter()
        let model = makeModel(changes: Self.stagedChanges, writer: writer)
        await loaded(model)

        model.toggleStaged(GitChange(status: "M ", path: "README.md"))
        await model.actionTask?.value

        #expect(writer.unstaged == ["README.md"])
        #expect(writer.staged.isEmpty)
    }

    @Test func toggleStagedOnAPartiallyStagedFileRunsAddAgain() async throws {
        let writer = FakeGitWriter()
        let model = makeModel(changes: [GitChange(status: "MM", path: "README.md")], writer: writer)
        await loaded(model)

        model.toggleStaged(GitChange(status: "MM", path: "README.md"))
        await model.actionTask?.value

        #expect(writer.staged == ["README.md"])
        #expect(writer.unstaged.isEmpty)
    }

    @Test func stageAllRunsAddAllAndReloads() async throws {
        let writer = FakeGitWriter()
        let model = makeModel(writer: writer)
        await loaded(model)

        model.stageAll()
        await model.actionTask?.value

        #expect(writer.stagedAll == [Self.path])
        #expect(model.phase == .ready)
    }

    @Test func aFailedStageKeepsTheListWithAnError() async throws {
        let writer = FakeGitWriter(stageError: GitServiceError.commandFailed(code: 1, stderr: "index.lock exists"))
        let model = makeModel(writer: writer)
        await loaded(model)

        model.toggleStaged(GitChange(status: " M", path: "README.md"))
        await model.actionTask?.value

        #expect(model.lastError?.contains("index.lock exists") == true)
        #expect(model.phase == .ready)
        #expect(model.changeSet != nil)
    }

    @Test func requestDiscardOpensTheConfirmation() async throws {
        let model = makeModel()
        await loaded(model)

        model.requestDiscard(GitChange(status: " M", path: "README.md"))
        #expect(model.discardRequest?.change.path == "README.md")

        model.cancelDiscard()
        #expect(model.discardRequest == nil)
    }

    @Test func requestDiscardIgnoresARename() async throws {
        let model = makeModel()
        await loaded(model)

        model.requestDiscard(GitChange(status: "R ", path: "README.md"))
        #expect(model.discardRequest == nil)
    }

    @Test func confirmDiscardCallsTheWriterAndBumpsTheRevision() async throws {
        let writer = FakeGitWriter()
        let model = makeModel(writer: writer)
        await loaded(model)

        model.requestDiscard(GitChange(status: " M", path: "README.md"))
        model.confirmDiscard()
        await model.actionTask?.value

        #expect(writer.discarded.count == 1)
        #expect(model.revision == 1)
        #expect(model.phase == .ready)
        #expect(model.discardRequest == nil)
    }

    @Test func aFailedDiscardKeepsTheListWithAnError() async throws {
        let writer = FakeGitWriter(discardError: GitServiceError.commandFailed(code: 1, stderr: "locked"))
        let model = makeModel(writer: writer)
        await loaded(model)

        model.requestDiscard(GitChange(status: " M", path: "README.md"))
        model.confirmDiscard()
        await model.actionTask?.value

        #expect(model.lastError?.contains("locked") == true)
        #expect(model.revision == 0)
        #expect(model.phase == .ready)
        #expect(model.changeSet != nil)
    }

    @Test func aLockedModelIgnoresStagingAndDiscard() async throws {
        let writer = FakeGitWriter()
        let model = makeModel(writer: writer)
        await loaded(model)
        model.isLocked = true

        model.toggleStaged(GitChange(status: " M", path: "README.md"))
        model.stageAll()
        model.requestDiscard(GitChange(status: " M", path: "README.md"))
        await model.actionTask?.value

        #expect(writer.staged.isEmpty)
        #expect(writer.stagedAll.isEmpty)
        #expect(model.discardRequest == nil)
        #expect(!model.canMutate)
    }
}
