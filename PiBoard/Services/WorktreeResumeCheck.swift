import Foundation

/// Resolves where a task's Pi session must resume. Shared by the preparation sheet and the
/// terminal workspace so both refuse the same broken worktrees.
enum WorktreeResumeCheck: Equatable, Sendable {
    case ok(URL)
    case missing
    case invalid(String)

    /// Current-tree tasks resume in the project folder; that path is validated at launch.
    /// A worktree task never falls back to the project root.
    static func run(task: BoardTask, project: Project, worktrees: WorktreeServicing) async -> WorktreeResumeCheck {
        switch task.runContext ?? .current {
        case .current:
            return .ok(project.path)
        case .worktree:
            guard let path = task.worktreePath, let branch = task.worktreeBranch else { return .missing }
            switch await worktrees.validate(WorktreeInfo(path: path, branch: branch)) {
            case .valid:
                return .ok(path)
            case .pathMissing:
                return .missing
            case .notAWorktree:
                return .invalid("The folder is not a Git worktree.")
            case .branchMismatch(let actual):
                return .invalid("Expected branch \(branch), found \(actual ?? "a detached HEAD").")
            }
        }
    }
}
