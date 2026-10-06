import SwiftUI

/// Shown when a resume is refused because the task's Pi session file is gone. Start Fresh
/// asks for confirmation; the caller then gives the task a new session ID and launches.
struct SessionNotFoundBanner: View {
    let sessionID: UUID
    var actionDisabled = false
    let onStartFresh: () -> Void
    let onCancel: () -> Void
    @State private var showsConfirmation = false

    var body: some View {
        BannerView(
            systemImage: "exclamationmark.triangle",
            title: "Pi session not found",
            message: PiProcessManager.LaunchError.sessionNotFound(sessionID).localizedDescription,
            actionTitle: "Start Fresh",
            action: { showsConfirmation = true },
            actionDisabled: actionDisabled,
            secondaryActionTitle: "Cancel",
            secondaryAction: onCancel
        )
        .confirmationDialog("Start a new Pi session?", isPresented: $showsConfirmation) {
            Button("Start Fresh", role: .destructive, action: onStartFresh)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The task gets a new Pi session ID. Its prompt, run context and worktree stay as they are.")
        }
    }
}
