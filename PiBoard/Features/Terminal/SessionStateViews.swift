import SwiftUI

private let exitedOverlayPadding: CGFloat = 24
private let exitedOverlayCornerRadius: CGFloat = 12
private let exitedOverlayMaxWidth: CGFloat = 320
private let stateViewSpacing: CGFloat = 12
private let notRunningSystemImage = "terminal"
private let exitedSystemImage = "xmark.circle"

/// What the workspace shows in place of a terminal or chat when no process is running; shared by both interfaces.
struct SessionNotRunningView: View {
    let task: BoardTask
    let isCheckingResume: Bool
    let onResume: () -> Void
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(spacing: stateViewSpacing) {
            ContentUnavailableView(
                AgentStrings.notRunning(task.agent),
                systemImage: notRunningSystemImage,
                description: Text(
                    task.sessionID != nil
                        ? (isCheckingResume
                            ? "Resuming the previous session..."
                            : "Resume to continue the previous session.")
                        : "\(AgentStrings.start(task.agent)) from the task preparation."
                )
            )
            if task.sessionID != nil {
                Button(AgentStrings.resume(task.agent), action: onResume)
                    .buttonStyle(.borderedProminent)
                    .disabled(isCheckingResume)
                    .accessibilityIdentifier(AccessibilityID.terminalResume)
            } else {
                Button("Prepare and Start") {
                    environment.board.pendingPreparationTaskID = task.id
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown over a session whose process has ended; shared by the terminal and the chat.
struct SessionExitedOverlay: View {
    let task: BoardTask?
    let agentKind: AgentKind
    let exitCode: Int32?
    let isCheckingResume: Bool
    let onResume: () -> Void
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(spacing: stateViewSpacing) {
            Image(systemName: exitedSystemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(AgentStrings.exited(agentKind, code: exitCode))
                .font(.headline)
            HStack {
                if let task, task.sessionID != nil {
                    Button(AgentStrings.resume(task.agent), action: onResume)
                        .buttonStyle(.borderedProminent)
                        .disabled(isCheckingResume)
                        .accessibilityIdentifier(AccessibilityID.terminalResume)
                }
                Button("Back to Board") {
                    environment.board.openTerminalTaskID = nil
                }
            }
        }
        .padding(exitedOverlayPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: exitedOverlayCornerRadius))
        .frame(maxWidth: exitedOverlayMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pointerStyle(.default)
    }
}
