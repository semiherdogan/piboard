import Foundation
import Testing
@testable import PiBoard

struct TaskPresentationTests {
    @Test func inProgressTaskWithSessionIsResumableWhenNotStarted() {
        let task = makeTask(status: .inProgress, sessionID: UUID(), runContext: .current)
        let badge = TaskPresentation.badge(for: task, runtimeState: .notStarted)
        #expect(badge?.label == TaskPresentation.resumableLabel)
        #expect(badge?.systemImage == TaskPresentation.resumableSystemImage)
    }

    @Test func existingWorktreeIsResumable() {
        let task = makeTask(status: .inProgress, sessionID: UUID(), runContext: .worktree)
        let badge = TaskPresentation.badge(for: task, runtimeState: .notStarted, worktreeExists: true)
        #expect(badge?.label == TaskPresentation.resumableLabel)
    }

    @Test func missingWorktreeReplacesResumable() {
        let task = makeTask(status: .inProgress, sessionID: UUID(), runContext: .worktree)
        let badge = TaskPresentation.badge(for: task, runtimeState: .notStarted, worktreeExists: false)
        #expect(badge?.label == TaskPresentation.worktreeMissingLabel)
        #expect(badge?.systemImage == TaskPresentation.worktreeMissingSystemImage)
    }

    @Test func runningTaskShowsRuntimeState() {
        let task = makeTask(status: .inProgress, sessionID: UUID(), runContext: .worktree)
        let badge = TaskPresentation.badge(for: task, runtimeState: .running, worktreeExists: false)
        #expect(badge?.label == TaskRuntimeState.running.label)
        #expect(badge?.systemImage == TaskRuntimeState.running.systemImage)
    }

    @Test func backlogTaskHasNoBadge() {
        let task = makeTask(status: .backlog, sessionID: UUID(), runContext: .current)
        #expect(TaskPresentation.badge(for: task, runtimeState: .notStarted) == nil)
    }

    @Test func inProgressTaskWithoutSessionHasNoBadge() {
        let task = makeTask(status: .inProgress, sessionID: nil, runContext: nil)
        #expect(TaskPresentation.badge(for: task, runtimeState: .notStarted) == nil)
    }

    @Test func worktreeExistsChecksDiskOnlyForInProgressWorktreeTasks() {
        var task = makeTask(status: .inProgress, sessionID: UUID(), runContext: .worktree)
        task.worktreePath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(TaskPresentation.worktreeExists(for: task) == false)

        task.worktreePath = FileManager.default.temporaryDirectory
        #expect(TaskPresentation.worktreeExists(for: task) == true)

        task.status = .backlog
        #expect(TaskPresentation.worktreeExists(for: task) == nil)
    }

    private func makeTask(status: TaskStatus, sessionID: UUID?, runContext: RunContext?) -> BoardTask {
        BoardTask(
            id: UUID(),
            projectId: UUID(),
            title: "Task",
            prompt: "",
            status: status,
            position: 0,
            piSessionId: sessionID,
            runContext: runContext,
            worktreePath: nil,
            worktreeBranch: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
