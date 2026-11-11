import Foundation

/// Moves a task's live session between the terminal and the native chat: stops the running
/// process, records the new interface, then resumes the same session there.
@MainActor
struct SessionInterfaceSwitcher {
    private let board: BoardModel
    private let processes: AgentProcessManager
    private let resumer: AgentSessionResumer
    private let gracePeriod: TimeInterval

    static let stillRunningMessage = "The running session did not stop."

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
            await stopAndWait(taskID: task.id)
            // Resuming over a live process would break the one-live-session rule, so leave everything as it was.
            if processes.runtimeState(for: task.id).isActive { return .failed(Self.stillRunningMessage) }
        }
        board.setInterface(interface, for: task.id)
        // The resumer routes by `task.interface`, so it needs the copy that carries the new value.
        guard let updated = board.tasks.first(where: { $0.id == task.id }), updated.sessionID != nil else { return nil }
        return await resumer.resume(task: updated, project: project, sharesCurrentTree: sharesCurrentTree)
    }

    private func stopAndWait(taskID: UUID) async {
        processes.stop(taskID: taskID)
        if await waitUntilInactive(taskID: taskID) { return }
        processes.forceKill(taskID: taskID)
        _ = await waitUntilInactive(taskID: taskID)
    }

    private func waitUntilInactive(taskID: UUID) async -> Bool {
        let deadline = Date().addingTimeInterval(gracePeriod)
        while processes.runtimeState(for: taskID).isActive, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(Int(ProcessQuitPolicy.pollInterval * 1000)))
        }
        return !processes.runtimeState(for: taskID).isActive
    }
}
