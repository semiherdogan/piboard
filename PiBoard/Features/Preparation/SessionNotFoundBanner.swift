import SwiftUI

/// Shown when a resume is refused because the task's Pi session file is gone. With
/// `confirmsInline` the Start Fresh button asks first and the caller launches a new session;
/// without it the button hands over to the preparation sheet, which does its own confirming.
struct SessionNotFoundBanner: View {
    private static let startFreshTitle = "Start Fresh"
    // The ellipsis marks a button that leads to another dialog, as on the rest of macOS.
    private static let openPreparationTitle = "Start Fresh..."

    let sessionID: UUID
    var actionDisabled = false
    var confirmsInline = true
    let onStartFresh: () -> Void
    let onCancel: () -> Void
    @State private var showsConfirmation = false

    var body: some View {
        BannerView(
            systemImage: "exclamationmark.triangle",
            title: "Pi session not found",
            message: PiProcessManager.LaunchError.sessionNotFound(sessionID).localizedDescription,
            actionTitle: confirmsInline ? Self.startFreshTitle : Self.openPreparationTitle,
            action: { if confirmsInline { showsConfirmation = true } else { onStartFresh() } },
            actionDisabled: actionDisabled,
            secondaryActionTitle: "Cancel",
            secondaryAction: onCancel
        )
        .confirmationDialog("Start a new Pi session?", isPresented: $showsConfirmation) {
            Button(Self.startFreshTitle, role: .destructive, action: onStartFresh)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The task gets a new Pi session ID. Its prompt, run context and worktree stay as they are.")
        }
    }
}
