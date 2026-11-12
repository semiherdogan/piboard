import Foundation

/// Moves a task's live session between the terminal and the native chat: stops the running
/// process, records the new interface, then resumes the same session there.
@MainActor
struct SessionInterfaceSwitcher {
    private let board: BoardModel
    private let processes: AgentProcessManager
    private let resumer: AgentSessionResumer
    private let gracePeriod: TimeInterval

    static let stillRunningMessage = AgentProcessManager.stillRunningMessage

    init(
        board: BoardModel,
        processes: AgentProcessManager,
        resumer: AgentSessionResumer,
        gracePeriod: TimeInterval = ProcessQuitPolicy.gracePeriod
    ) {
        self.board = board
        self.processes = processes
        self.resumer = resumer
        self.gracePeriod = gracePeriod
    }

    /// Nil when the task has no session to resume; the interface is still recorded for the next launch.
    func switchInterface(task: BoardTask, project: Project, to interface: SessionInterface, sharesCurrentTree: Bool) async -> ResumeOutcome? {
        if processes.runtimeState(for: task.id).isActive {
            // Resuming over a live process would break the one-live-session rule, so leave everything as it was.
            guard await processes.stopAndWait(taskID: task.id, gracePeriod: gracePeriod) else {
                return .failed(Self.stillRunningMessage)
            }
        }
        board.setInterface(interface, for: task.id)
        // The resumer routes by `task.interface`, so it needs the copy that carries the new value.
        guard let updated = board.tasks.first(where: { $0.id == task.id }), updated.sessionID != nil else { return nil }
        return await resumer.resume(task: updated, project: project, sharesCurrentTree: sharesCurrentTree)
    }
}
