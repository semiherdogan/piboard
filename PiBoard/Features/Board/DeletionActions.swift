import Foundation
import Observation

/// Builds the plan behind a delete confirmation and carries it out.
///
/// The order matters: an agent has to be stopped before its worktree can be removed, and the
/// database rows go last so a failure part way through still leaves the task visible rather than
/// stranding the resources it owns.
@MainActor
@Observable
final class DeletionActions {
    // Exposed so tests can await completion.
    private(set) var actionTask: Task<Void, Never>?

    private let board: BoardModel
    private let processes: PiProcessManager
    private let worktrees: WorktreeServicing
    private let attention: TaskAttention
    private let shells: ShellSessions

    init(board: BoardModel, processes: PiProcessManager, worktrees: WorktreeServicing, attention: TaskAttention, shells: ShellSessions) {
        self.board = board
        self.processes = processes
        self.worktrees = worktrees
        self.attention = attention
        self.shells = shells
    }

    /// Starts the delete from the confirmation button; `actionTask` lets tests await it.
    func delete(_ plan: DeletionPlan) {
        actionTask = Task { await self.perform(plan) }
    }

    func plan(forProject project: Project) -> DeletionPlan {
        let tasks = board.tasks(for: project.id)
        return DeletionPlan(
            subject: .project(id: project.id, name: project.name),
            taskIDs: tasks.map(\.id),
            runningTaskIDs: tasks.lazy.filter { self.processes.runtimeState(for: $0.id).isActive }.map(\.id),
            worktrees: tasks.compactMap { worktree(for: $0, project: project) }
        )
    }

    func plan(forTask task: BoardTask) -> DeletionPlan {
        let project = board.projects.first { $0.id == task.projectId }
        return DeletionPlan(
            subject: .task(id: task.id, title: task.title),
            taskIDs: [task.id],
            runningTaskIDs: processes.runtimeState(for: task.id).isActive ? [task.id] : [],
            worktrees: project.flatMap { worktree(for: task, project: $0) }.map { [$0] } ?? []
        )
    }

    /// Only a worktree still on disk is worth removing; a task pointing at a folder that is gone
    /// just needs its registration pruned, which `perform` does for the repository anyway.
    private func worktree(for task: BoardTask, project: Project) -> PlannedWorktreeRemoval? {
        guard task.runContext == .worktree,
              let path = task.worktreePath,
              let branch = task.worktreeBranch,
              ProjectPathService.exists(path)
        else { return nil }
        return PlannedWorktreeRemoval(
            taskID: task.id,
            info: WorktreeInfo(path: path, branch: branch),
            repository: project.path
        )
    }

    func perform(_ plan: DeletionPlan) async {
        if plan.hasRunningAgents {
            await processes.stopAndForget(taskIDs: plan.taskIDs)
        } else {
            for taskID in plan.taskIDs {
                processes.forget(taskID: taskID)
            }
        }

        // Forced: the confirmation already said uncommitted changes would be lost, and stopping
        // at the first dirty worktree would leave the delete half done.
        var failures: [String] = []
        for removal in plan.worktrees {
            do {
                try await worktrees.remove(removal.info, force: true)
            } catch {
                failures.append(ProjectPathService.abbreviated(removal.info.path))
            }
        }
        for repository in Set(plan.worktrees.map(\.repository)) {
            try? await worktrees.prune(repository: repository)
        }

        for taskID in plan.taskIDs {
            attention.clear(taskID: taskID)
        }

        switch plan.subject {
        case .project(let id, _):
            shells.close(projectID: id)
            board.deleteProject(id: id)
        case .task(let id, _):
            board.deleteTask(id)
        }

        if !failures.isEmpty {
            board.lastError = "Deleted, but these worktree folders could not be removed: \(failures.joined(separator: ", "))"
        }
    }
}
