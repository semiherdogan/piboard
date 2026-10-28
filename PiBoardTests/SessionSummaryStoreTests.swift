import Foundation
import Testing
@testable import PiBoard

@MainActor
struct SessionSummaryStoreTests {
    private static let sessionFilePrefix = "2026-10-06T13-02-02-447Z_"
    private static let sessionFileExtension = ".jsonl"
    private static let sessionContent = [
        #"{"type":"message","timestamp":"2026-10-06T13:02:03.000Z","message":{"role":"user","content":"Hi"}}"#,
        #"{"type":"message","timestamp":"2026-10-06T13:02:04.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Hello"}]}}"#
    ].joined(separator: "\n")

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTask(sessionID: UUID?, projectID: UUID = UUID()) -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: projectID,
            agent: .default,
            title: "Task",
            prompt: "",
            status: .inProgress,
            position: 0,
            sessionID: sessionID?.uuidString,
            runContext: .current,
            worktreePath: nil,
            worktreeBranch: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeProject(path: URL) -> Project {
        Project(id: UUID(), name: "Project", path: path, defaultAgent: .default, createdAt: Date(), updatedAt: Date())
    }

    @Test func refreshReadsTheSessionFile() async throws {
        let agentDir = try makeTempDirectory()
        let cwd = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: agentDir)
            try? FileManager.default.removeItem(at: cwd)
        }
        let sessionID = UUID()
        let directory = PiSessionLocator.sessionsDirectory(agentDir: agentDir, cwd: cwd)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = Self.sessionFilePrefix + sessionID.uuidString.lowercased() + Self.sessionFileExtension
        try Data(Self.sessionContent.utf8).write(to: directory.appendingPathComponent(name))
        let store = SessionSummaryStore(agents: .pi(agentDirectory: agentDir))
        let task = makeTask(sessionID: sessionID)

        store.refresh(task: task, project: makeProject(path: cwd))
        await store.refreshTasks[task.id]?.value

        #expect(store.summary(for: task.id)?.turnCount == 1)
    }

    @Test func taskWithoutSessionIsForgotten() async throws {
        let agentDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: agentDir) }
        let store = SessionSummaryStore(agents: .pi(agentDirectory: agentDir))
        let task = makeTask(sessionID: nil)

        store.refresh(task: task, project: makeProject(path: agentDir))

        #expect(store.summary(for: task.id) == nil)
        #expect(store.refreshTasks[task.id] == nil)
    }

    @Test func missingFileLeavesNoSummary() async throws {
        let agentDir = try makeTempDirectory()
        let cwd = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: agentDir)
            try? FileManager.default.removeItem(at: cwd)
        }
        let store = SessionSummaryStore(agents: .pi(agentDirectory: agentDir))
        let task = makeTask(sessionID: UUID())

        store.refresh(task: task, project: makeProject(path: cwd))
        await store.refreshTasks[task.id]?.value

        #expect(store.summary(for: task.id) == nil)
    }
}
