import Foundation
import Observation

struct WorktreeRemovalRequest: Equatable {
    enum Kind: Equatable {
        case clean
        case dirty(changes: [GitChange])
        // The folder is gone but the task still records it; only the fields are cleared.
        case missing
    }

    let taskID: UUID
    let info: WorktreeInfo
    let repository: URL
    let kind: Kind

    static let maxListedChanges = 10

    var title: String {
        switch kind {
        case .clean: "Remove worktree?"
        case .dirty: "Remove worktree with uncommitted changes?"
        case .missing: "Worktree folder not found"
        }
    }

    var message: String {
        let branchKept = "The branch \(info.branch) is kept."
        switch kind {
        case .clean:
            return branchKept
        case .dirty(let changes):
            var lines = changes.prefix(Self.maxListedChanges).map(\.path)
            if changes.count > Self.maxListedChanges {
                lines.append("and \(changes.count - Self.maxListedChanges) more")
            }
            return lines.joined(separator: "\n") + "\n\nThese changes will be lost. " + branchKept
        case .missing:
            return "Nothing exists at \(ProjectPathService.abbreviated(info.path)) anymore. Forget it to clear the task's worktree. " + branchKept
        }
    }

    var confirmTitle: String {
        switch kind {
        case .clean: WorktreeActions.removeTitle
        case .dirty: WorktreeActions.removeAnywayTitle
        case .missing: WorktreeActions.forgetTitle
        }
    }

    var isDestructive: Bool {
        kind != .missing
    }

    var force: Bool {
        if case .dirty = kind { true } else { false }
    }
}

@MainActor
@Observable
final class WorktreeActions {
    nonisolated static let removeMenuTitle = "Remove Worktree..."
    nonisolated static let removeTitle = "Remove Worktree"
    nonisolated static let removeAnywayTitle = "Remove Anyway"
    nonisolated static let forgetTitle = "Forget Worktree"
    nonisolated static let activeSessionMessage = "Stop the Pi session before removing the worktree."

    // Presented by BoardView or TerminalWorkspaceView; cleared before the mutation runs.
    var removalRequest: WorktreeRemovalRequest?
    // Bumped after each removal so the board git row refreshes.
    private(set) var revision = 0
    // Exposed so tests can await completion.
    private(set) var actionTask: Task<Void, Never>?

    private let board: BoardModel
    private let processes: PiProcessManager
    private let git: GitServicing
    private let worktrees: WorktreeServicing

    init(board: BoardModel, processes: PiProcessManager, git: GitServicing, worktrees: WorktreeServicing) {
        self.board = board
        self.processes = processes
        self.git = git
        self.worktrees = worktrees
    }

    func isBlocked(_ taskID: UUID) -> Bool {
        processes.runtimeState(for: taskID).isActive
    }

    /// Inspects the worktree and sets `removalRequest` for the caller to confirm.
    func removeWorktree(for taskID: UUID) async {
        guard let task = board.tasks.first(where: { $0.id == taskID }),
              let path = task.worktreePath,
              let branch = task.worktreeBranch,
              let project = board.projects.first(where: { $0.id == task.projectId }) else { return }
        guard !isBlocked(taskID) else {
            board.lastError = Self.activeSessionMessage
            return
        }
        let info = WorktreeInfo(path: path, branch: branch)
        let kind: WorktreeRemovalRequest.Kind
        if await worktrees.validate(info) == .pathMissing {
            kind = .missing
        } else {
            do {
                let changes = try await git.status(at: path)
                kind = changes.isEmpty ? .clean : .dirty(changes: changes)
            } catch {
                board.lastError = "Could not read the worktree status: \(error.localizedDescription)"
                return
            }
        }
        removalRequest = WorktreeRemovalRequest(taskID: taskID, info: info, repository: project.path, kind: kind)
    }

    /// Starts the removal from the button handler; `actionTask` lets tests await it.
    func requestRemoval(for taskID: UUID) {
        actionTask = Task { await self.removeWorktree(for: taskID) }
    }

    func confirmRemoval() {
        guard let request = removalRequest else { return }
        removalRequest = nil
        actionTask = Task { await self.perform(request) }
    }

    func cancelRemoval() {
        removalRequest = nil
    }

    func perform(_ request: WorktreeRemovalRequest) async {
        // A session may have started while the confirmation was up.
        guard !isBlocked(request.taskID) else {
            board.lastError = Self.activeSessionMessage
            return
        }
        switch request.kind {
        case .clean, .dirty:
            do {
                try await worktrees.remove(request.info, force: request.force)
            } catch {
                board.lastError = "Could not remove the worktree: \(error.localizedDescription)"
                return
            }
        case .missing:
            // Best effort: a stale entry only blocks re-adding a worktree at the same path.
            try? await worktrees.prune(repository: request.repository)
        }
        board.detachWorktree(for: request.taskID)
        revision += 1
    }
}
