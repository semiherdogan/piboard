import Foundation

enum TaskPresentation {
    static let resumableLabel = "Resumable"
    static let resumableSystemImage = "arrow.clockwise.circle"
    static let worktreeMissingLabel = "Worktree missing"
    static let worktreeMissingSystemImage = "exclamationmark.triangle"

    /// Runtime badge for a task. After a restart every process state is `.notStarted`, so an
    /// In Progress task is flagged as resumable, or as blocked when its worktree is gone.
    /// `worktreeExists` is nil when the caller did not check the disk.
    static func badge(
        for task: BoardTask,
        runtimeState: TaskRuntimeState,
        worktreeExists: Bool? = nil
    ) -> (systemImage: String, label: String)? {
        guard runtimeState == .notStarted else {
            return (runtimeState.systemImage, runtimeState.label)
        }
        guard task.status == .inProgress else { return nil }
        if task.runContext == .worktree, worktreeExists == false {
            return (worktreeMissingSystemImage, worktreeMissingLabel)
        }
        guard task.piSessionId != nil else { return nil }
        return (resumableSystemImage, resumableLabel)
    }

    /// Only In Progress worktree tasks are checked, so other cards never touch the disk.
    static func worktreeExists(for task: BoardTask) -> Bool? {
        guard task.status == .inProgress, task.runContext == .worktree else { return nil }
        guard let worktreePath = task.worktreePath else { return false }
        return FileManager.default.fileExists(atPath: worktreePath.path)
    }
}
