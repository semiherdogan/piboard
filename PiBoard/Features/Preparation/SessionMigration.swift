import Foundation

/// Pure rules for the "Migrate to <agent>" flow.
enum SessionMigration {
    /// What the sheet asks before it stops the source session at confirm time.
    enum Confirmation: Equatable {
        case none
        case stopsRunning
        case interruptsWorking
    }

    static let previousSessionStoppedNote = " The previous session was stopped and can be resumed."

    /// Same rule as `BoardModel.requestStop`: only a provably idle agent stops without a dialog; working, blocked or unknown activity asks.
    static func confirmation(isActive: Bool, activity: AgentActivity?) -> Confirmation {
        guard isActive else { return .none }
        return activity == .idle ? .stopsRunning : .interruptsWorking
    }

    /// The transcript to apply after the source stopped, or nil to keep what the user reviewed.
    static func transcriptAfterStop(
        current: SessionTranscript,
        reread: SessionTranscript?,
        isEdited: Bool
    ) -> SessionTranscript? {
        guard !isEdited else { return nil }
        return reread
    }

    /// A failure after the stop must tell the user the source can be resumed.
    static func failureMessage(_ message: String, stoppedSource: Bool) -> String {
        stoppedSource ? message + previousSessionStoppedNote : message
    }

    static func canMigrate(_ task: BoardTask) -> Bool {
        task.sessionID != nil
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
