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

    @Test func headerReadsNotRunningForSessionWithoutProcess() {
        let task = makeTask(status: .inProgress, sessionID: UUID(), runContext: .current)

        let header = TaskPresentation.headerBadge(for: task, runtimeState: .notStarted)

        #expect(header.label == TaskPresentation.notRunningLabel)
        #expect(header.systemImage == TaskPresentation.resumableSystemImage)
        #expect(TaskPresentation.badge(for: task, runtimeState: .notStarted)?.label == TaskPresentation.resumableLabel)
    }

    @Test func headerShowsRuntimeStateOtherwise() {
        let running = makeTask(status: .inProgress, sessionID: UUID(), runContext: .current)
        let fresh = makeTask(status: .inProgress, sessionID: nil, runContext: nil)

        #expect(TaskPresentation.headerBadge(for: running, runtimeState: .running).label == TaskRuntimeState.running.label)
        #expect(TaskPresentation.headerBadge(for: fresh, runtimeState: .notStarted).label == TaskRuntimeState.notStarted.label)
    }

    @Test func runningBadgeReflectsAgentActivity() {
        let task = makeTask(status: .inProgress, sessionID: UUID(), runContext: .current)

        let working = TaskPresentation.badge(for: task, runtimeState: .running, agentActivity: .working)
        #expect(working?.label == TaskPresentation.workingLabel)
        #expect(working?.systemImage == TaskRuntimeState.running.systemImage)

        let idle = TaskPresentation.badge(for: task, runtimeState: .running, agentActivity: .idle)
        #expect(idle?.label == TaskPresentation.idleLabel)
        #expect(idle?.systemImage == TaskPresentation.idleSystemImage)

        let unknown = TaskPresentation.badge(for: task, runtimeState: .running, agentActivity: nil)
        #expect(unknown?.label == TaskRuntimeState.running.label)
    }

    @Test func headerReflectsAgentActivity() {
        let task = makeTask(status: .inProgress, sessionID: UUID(), runContext: .current)

        let working = TaskPresentation.headerBadge(for: task, runtimeState: .running, agentActivity: .working)
        #expect(working.label == TaskPresentation.workingLabel)
        #expect(working.systemImage == TaskRuntimeState.running.systemImage)

        let idle = TaskPresentation.headerBadge(for: task, runtimeState: .running, agentActivity: .idle)
        #expect(idle.label == TaskPresentation.idleLabel)
        #expect(idle.systemImage == TaskPresentation.idleSystemImage)

        let unknown = TaskPresentation.headerBadge(for: task, runtimeState: .running, agentActivity: nil)
        #expect(unknown.label == TaskRuntimeState.running.label)
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
