import Foundation

/// Pure rules for the "Migrate to <agent>" flow.
enum SessionMigration {
    static func canMigrate(_ task: BoardTask, isRunning: Bool) -> Bool {
        task.sessionID != nil && !isRunning
    }

    static func targets(for task: BoardTask, enabled: [AgentKind]) -> [AgentKind] {
        enabled.filter { $0 != task.agent }
    }

    static func launchDirectory(task: BoardTask, project: Project) -> (context: RunContext, cwd: URL) {
        if task.runContext == .worktree, let worktreePath = task.worktreePath {
            return (.worktree, worktreePath)
        }
        return (.current, project.path)
    }
}
