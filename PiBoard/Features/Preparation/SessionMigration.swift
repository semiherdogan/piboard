import Foundation

/// Pure rules for the "Migrate to <agent>" flow.
enum SessionMigration {
    static func canMigrate(_ task: BoardTask, isRunning: Bool) -> Bool {
        task.sessionID != nil && !isRunning
    }

    /// Every enabled agent; the task's own agent is a handoff to a fresh session of it.
    static func targets(for task: BoardTask, enabled: [AgentKind]) -> [AgentKind] {
        enabled
    }

    static func launchDirectory(task: BoardTask, project: Project) -> (context: RunContext, cwd: URL) {
        if task.runContext == .worktree, let worktreePath = task.worktreePath {
            return (.worktree, worktreePath)
        }
        return (.current, project.path)
    }
}
