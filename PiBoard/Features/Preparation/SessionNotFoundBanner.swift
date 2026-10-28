import SwiftUI

/// Shown when a resume is refused because the task's Pi session file is gone. With
/// `confirmsInline` the Start Fresh button asks first and the caller launches a new session;
/// without it the button hands over to the preparation sheet, which does its own confirming.
struct SessionNotFoundBanner: View {
    private static let startFreshTitle = "Start Fresh"
    // The ellipsis marks a button that leads to another dialog, as on the rest of macOS.
    private static let openPreparationTitle = "Start Fresh..."

    let kind: AgentKind
    let sessionID: String
    var actionDisabled = false
    var confirmsInline = true
    let onStartFresh: () -> Void
    let onCancel: () -> Void
    @State private var showsConfirmation = false

    var body: some View {
        BannerView(
            systemImage: "exclamationmark.triangle",
            title: AgentStrings.sessionNotFound(kind),
            message: AgentProcessManager.LaunchError.sessionNotFound(sessionID, kind: kind).localizedDescription,
            actionTitle: confirmsInline ? Self.startFreshTitle : Self.openPreparationTitle,
            action: { if confirmsInline { showsConfirmation = true } else { onStartFresh() } },
            actionDisabled: actionDisabled,
            secondaryActionTitle: "Cancel",
            secondaryAction: onCancel
        )
        .confirmationDialog(AgentStrings.startNewSessionQuestion(kind), isPresented: $showsConfirmation) {
            Button(Self.startFreshTitle, role: .destructive, action: onStartFresh)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AgentStrings.newSessionIDNote(kind))
        }
    }
}
