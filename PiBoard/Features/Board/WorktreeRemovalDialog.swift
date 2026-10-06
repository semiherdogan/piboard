import SwiftUI

extension View {
    func worktreeRemovalDialog(_ actions: WorktreeActions) -> some View {
        modifier(WorktreeRemovalDialog(actions: actions))
    }
}

private struct WorktreeRemovalDialog: ViewModifier {
    let actions: WorktreeActions

    func body(content: Content) -> some View {
        content.confirmationDialog(
            actions.removalRequest?.title ?? "",
            isPresented: isPresented,
            presenting: actions.removalRequest
        ) { request in
            Button(request.confirmTitle, role: request.isDestructive ? .destructive : nil) {
                actions.confirmRemoval()
            }
            Button("Cancel", role: .cancel) {
                actions.cancelRemoval()
            }
        } message: { request in
            Text(request.message)
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { actions.removalRequest != nil },
            set: { isPresented in
                if !isPresented {
                    actions.cancelRemoval()
                }
            }
        )
    }
}
