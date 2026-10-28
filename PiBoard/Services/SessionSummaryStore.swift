import Foundation
import Observation

/// Summaries per task, refreshed from disk when something about the session may have changed.
/// Reads happen off the main actor; a missing or unreadable file clears the entry.
@MainActor
@Observable
final class SessionSummaryStore {
    private(set) var summaries: [UUID: SessionSummary] = [:]
    // Exposed so tests can await a refresh.
    private(set) var refreshTasks: [UUID: Task<Void, Never>] = [:]
    private let agentDirectory: URL

    init(agentDirectory: URL = PiSessionLocator.defaultAgentDirectory()) {
        self.agentDirectory = agentDirectory
    }

    func summary(for taskID: UUID) -> SessionSummary? {
        summaries[taskID]
    }

    /// The cwd decides the sessions folder, exactly as the locator and the deletion plan compute it.
    func refresh(task: BoardTask, project: Project) {
        guard let sessionID = task.piSessionId else {
            forget(taskID: task.id)
            return
        }
        let cwd = task.runContext == .worktree ? (task.worktreePath ?? project.path) : project.path
        let agentDirectory = agentDirectory
        let taskID = task.id
        refreshTasks[taskID]?.cancel()
        refreshTasks[taskID] = Task { [weak self] in
            let summary = await Task.detached(priority: .utility) { () -> SessionSummary? in
                guard let file = PiSessionLocator.sessionFile(sessionID: sessionID, cwd: cwd, agentDir: agentDirectory) else { return nil }
                return try? PiSessionReader.read(file: file)
            }.value
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
