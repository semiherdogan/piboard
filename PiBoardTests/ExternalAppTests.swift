import Foundation
import Testing
@testable import PiBoard

struct FakeExternalAppService: ExternalAppServicing {
    var installed: Set<ExternalApp> = [.finder]

    func isAvailable(_ app: ExternalApp) -> Bool {
        installed.contains(app)
    }

    func open(_ url: URL, in app: ExternalApp) async throws {
        guard installed.contains(app) else { throw ExternalAppError.notInstalled(app) }
    }
}

@MainActor
struct ExternalAppTests {
    private func makeDatabase() throws -> Database {
        let database = try Database(path: ":memory:")
        try MigrationRunner.migrate(database)
        return database
    }

    private func makeProject(path: URL) -> Project {
        Project(id: UUID(), name: "Project", path: path, createdAt: Date(), updatedAt: Date())
    }

    private func makeTask(projectID: UUID, runContext: RunContext?, worktreePath: URL?) -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: projectID,
            title: "Task",
            prompt: "",
            status: .inProgress,
            position: 0,
            piSessionId: nil,
            runContext: runContext,
            worktreePath: worktreePath,
            worktreeBranch: worktreePath.map { _ in "piboard/task" },
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @Test func finderIsAlwaysAvailable() {
        #expect(ExternalAppService().isAvailable(.finder))
    }

    @Test func targetIsWorktreeWhenItExists() throws {
        let worktree = try GitTestRepository.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: worktree) }
        let project = makeProject(path: URL(fileURLWithPath: "/tmp/project"))
        let task = makeTask(projectID: project.id, runContext: .worktree, worktreePath: worktree)

        #expect(ExternalAppActions.targetURL(for: task, project: project) == worktree)
    }

    @Test func targetFallsBackToProjectWhenWorktreeMissingOrNotUsed() throws {
        let worktree = try GitTestRepository.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: worktree) }
        let missing = worktree.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let project = makeProject(path: URL(fileURLWithPath: "/tmp/project"))

        let missingTask = makeTask(projectID: project.id, runContext: .worktree, worktreePath: missing)
        let currentTask = makeTask(projectID: project.id, runContext: .current, worktreePath: worktree)
        let unsetTask = makeTask(projectID: project.id, runContext: .worktree, worktreePath: nil)

        #expect(ExternalAppActions.targetURL(for: missingTask, project: project) == project.path)
        #expect(ExternalAppActions.targetURL(for: currentTask, project: project) == project.path)
        #expect(ExternalAppActions.targetURL(for: unsetTask, project: project) == project.path)
    }

    @Test func preferenceDefaults() throws {
        let preferences = AppPreferences(database: try makeDatabase())
        #expect(preferences.preferredEditor == .vsCode)
        #expect(preferences.preferredTerminal == .terminal)
    }

    @Test func preferencesRoundTrip() throws {
        let database = try makeDatabase()
        let first = AppPreferences(database: database)
        first.preferredEditor = .zed
        first.preferredTerminal = .iTerm

        let second = AppPreferences(database: database)
        #expect(second.preferredEditor == .zed)
        #expect(second.preferredTerminal == .iTerm)
    }

    @Test func installedAppsComeFromService() throws {
        let board = BoardModel(database: try makeDatabase())
        let actions = ExternalAppActions(service: FakeExternalAppService(installed: [.finder, .cursor]), board: board)

        #expect(actions.installedApps == [.finder, .cursor])
        #expect(!actions.isInstalled(.vsCode))
    }

    @Test func openingUninstalledAppReportsError() async throws {
        let board = BoardModel(database: try makeDatabase())
        let actions = ExternalAppActions(service: FakeExternalAppService(), board: board)

        actions.open(URL(fileURLWithPath: "/tmp"), in: .vsCode)
        await actions.openTask?.value

        #expect(board.lastError?.contains(ExternalAppError.notInstalled(.vsCode).localizedDescription) == true)
    }

    @Test func openingInstalledAppLeavesNoError() async throws {
        let board = BoardModel(database: try makeDatabase())
        let actions = ExternalAppActions(service: FakeExternalAppService(), board: board)

        actions.open(URL(fileURLWithPath: "/tmp"), in: .finder)
        await actions.openTask?.value

        #expect(board.lastError == nil)
    }
}
