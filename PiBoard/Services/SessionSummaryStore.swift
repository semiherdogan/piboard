import Foundation
import Observation

/// Summaries per task, refreshed from the agent when something about the session may have changed.
/// Adapters do their I/O off the main actor; a missing or unreadable session clears the entry.
@MainActor
@Observable
final class SessionSummaryStore {
    private(set) var summaries: [UUID: SessionSummary] = [:]
    // Exposed so tests can await a refresh.
    private(set) var refreshTasks: [UUID: Task<Void, Never>] = [:]
    private let agents: AgentRegistry

    init(agents: AgentRegistry) {
        self.agents = agents
    }

    func summary(for taskID: UUID) -> SessionSummary? {
        summaries[taskID]
    }

    /// The cwd decides the sessions folder, exactly as the locator and the deletion plan compute it.
    func refresh(task: BoardTask, project: Project) {
        guard let sessionID = task.sessionID else {
            forget(taskID: task.id)
            return
        }
        let cwd = task.runContext == .worktree ? (task.worktreePath ?? project.path) : project.path
        let adapter = agents.adapter(for: task)
        let taskID = task.id
        refreshTasks[taskID]?.cancel()
        refreshTasks[taskID] = Task { [weak self] in
            let summary = await adapter.readSessionSummary(id: sessionID, cwd: cwd)
            guard !Task.isCancelled, let self else { return }
            self.summaries[taskID] = summary
            self.refreshTasks[taskID] = nil
        }
    }

    func forget(taskID: UUID) {
        refreshTasks[taskID]?.cancel()
        refreshTasks[taskID] = nil
        summaries[taskID] = nil
    }
}
