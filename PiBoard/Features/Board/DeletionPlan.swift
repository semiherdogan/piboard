import Foundation

/// A worktree that a deletion is about to remove, kept with the task that owns it.
struct PlannedWorktreeRemoval: Equatable, Sendable {
    let taskID: UUID
    let info: WorktreeInfo
    /// The repository the worktree belongs to, needed to prune a stale registration.
    let repository: URL
}

/// Everything a delete is about to take with it, worked out before the confirmation is shown.
///
/// Deleting used to touch only the database, leaving the agent running and its worktree on disk
/// with no task left to reach either from. The plan exists so the dialog can say what will happen
/// and so the same list drives the cleanup afterwards.
struct DeletionPlan: Equatable, Sendable {
    enum Subject: Equatable, Sendable {
        case project(id: UUID, name: String)
        case task(id: UUID, title: String)

        var name: String {
            switch self {
            case .project(_, let name): name
            case .task(_, let title): title
            }
        }
    }

    let subject: Subject
    /// Every task the delete removes: the one task, or all tasks of the project.
    let taskIDs: [UUID]
    /// Tasks whose agent is starting, running or stopping; these get stopped first.
    let runningTaskIDs: [UUID]
    let worktrees: [PlannedWorktreeRemoval]

    var title: String {
        "Delete \(subject.name)?"
    }

    var confirmTitle: String {
        switch subject {
        case .project: hasRunningAgents ? "Stop Agents and Delete" : "Delete Project"
        case .task: hasRunningAgents ? "Stop Agent and Delete" : "Delete Task"
        }
    }

    var hasRunningAgents: Bool {
        !runningTaskIDs.isEmpty
    }

    /// Losing uncommitted work is the one part of this that cannot be undone, so it is stated
    /// plainly rather than folded into the worktree count.
    var message: String {
        var lines: [String] = []
        switch subject {
        case .project:
            lines.append("\(count(taskIDs.count, "task", "tasks")) will be deleted.")
        case .task:
            break
        }
        if hasRunningAgents {
            let verb = runningTaskIDs.count == 1 ? "is running and will be stopped." : "are running and will be stopped."
            lines.append("\(count(runningTaskIDs.count, "agent", "agents")) \(verb)")
        }
        if !worktrees.isEmpty {
            let pronoun = worktrees.count == 1 ? "it" : "them"
            lines.append("\(count(worktrees.count, "worktree", "worktrees")) will be removed, along with any uncommitted changes in \(pronoun).")
        }
        lines.append(trailer)
        return lines.joined(separator: "\n")
    }

    private var trailer: String {
        switch subject {
        case .project: "The project folder itself is not touched."
        case .task: "Pi session files are not deleted."
        }
    }

    private func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}
