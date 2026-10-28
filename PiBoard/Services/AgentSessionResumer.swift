import Foundation

/// Why a resume did not start, or that it did. Equatable so tests compare whole outcomes.
enum ResumeOutcome: Equatable {
    case started
    case worktreeMissing
    case worktreeInvalid(String)
    /// The session file is gone; `cwd` is the resolved launch directory for a Start Fresh.
    case sessionNotFound(sessionID: String, cwd: URL)
    case currentTreeBusy(ownerTaskID: UUID)
    case failed(String)
}

/// Resumes a task's saved agent session: validates the worktree first, then launches, and turns
/// the launch errors the views react to into one outcome. Shared by the preparation sheet and
/// the terminal workspace so both refuse the same broken worktrees and show the same cases.
@MainActor
struct AgentSessionResumer {
    private let processes: AgentProcessManager
    private let worktrees: WorktreeServicing

    init(processes: AgentProcessManager, worktrees: WorktreeServicing) {
        self.processes = processes
        self.worktrees = worktrees
    }

    /// Resumes in the context the session was started in; a task without a session id is a
    /// programming error upstream, so it reports `.failed`.
    func resume(task: BoardTask, project: Project, sharesCurrentTree: Bool) async -> ResumeOutcome {
        let outcome = await attempt(task: task, project: project, sharesCurrentTree: sharesCurrentTree)
        Diagnostics.git.info("resume task=\(task.id.uuidString, privacy: .public) outcome=\(String(describing: outcome), privacy: .public)")
        return outcome
    }

    private func attempt(task: BoardTask, project: Project, sharesCurrentTree: Bool) async -> ResumeOutcome {
        guard let sessionID = task.sessionID else {
            return .failed(AgentStrings.noSessionToResume(task.agent))
        }
        let cwd: URL
        switch await WorktreeResumeCheck.run(task: task, project: project, worktrees: worktrees) {
        case .ok(let resolved):
            cwd = resolved
        case .missing:
            return .worktreeMissing
        case .invalid(let reason):
            return .worktreeInvalid(reason)
        }
        do {
            _ = try processes.resume(
                task: task,
                project: project,
                runContext: task.runContext ?? .current,
                cwd: cwd,
                sessionID: sessionID,
                sharesCurrentTree: sharesCurrentTree
            )
            return .started
        } catch AgentProcessManager.LaunchError.sessionNotFound(let missingID, _) {
            return .sessionNotFound(sessionID: missingID, cwd: cwd)
        } catch AgentProcessManager.LaunchError.invalidSessionID(let invalidID) {
            // A session id this agent cannot read is as unusable as a missing file.
            return .sessionNotFound(sessionID: invalidID, cwd: cwd)
        } catch AgentProcessManager.LaunchError.currentTreeBusy(let ownerTaskID, _) {
            return .currentTreeBusy(ownerTaskID: ownerTaskID)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
