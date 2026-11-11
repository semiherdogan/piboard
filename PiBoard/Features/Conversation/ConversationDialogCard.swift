import SwiftUI

private let dialogCardSpacing: CGFloat = 10
private let dialogEditorMinHeight: CGFloat = 80
private let confirmTitle = "Confirm"
private let cancelTitle = "Cancel"
private let submitTitle = "Submit"
private let fallbackDialogTitle = "Pi needs your input"

/// Shows the oldest pending request from the agent above the composer; every answer goes back through `onAnswer`.
struct ConversationDialogCard: View {
    let dialog: ConversationDialog
    let onAnswer: (ConversationDialogAnswer) -> Void
    @State private var text: String

    init(dialog: ConversationDialog, onAnswer: @escaping (ConversationDialogAnswer) -> Void) {
        self.dialog = dialog
        self.onAnswer = onAnswer
        _text = State(initialValue: dialog.prefill ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dialogCardSpacing) {
            Text(dialog.title ?? fallbackDialogTitle)
                .font(.headline)
            if let message = dialog.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            controls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .conversationCard()
    }

    @ViewBuilder
    private var controls: some View {
        switch dialog.method {
        case .confirm:
            HStack {
                Button(confirmTitle) { onAnswer(.confirmed(true)) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.chatDialogConfirm)
                cancelButton(answer: .confirmed(false))
            }
        case .select:
            VStack(alignment: .leading, spacing: dialogCardSpacing) {
                ForEach(Array(dialog.options.enumerated()), id: \.offset) { index, option in
                    Button(option) { onAnswer(.value(option)) }
                        .accessibilityIdentifier("\(AccessibilityID.chatDialogOptionPrefix)\(index)")
                }
                cancelButton(answer: .cancelled)
            }
        case .input:
            VStack(alignment: .leading, spacing: dialogCardSpacing) {
                TextField(dialog.placeholder ?? "", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onAnswer(.value(text)) }
                    .accessibilityIdentifier(AccessibilityID.chatDialogField)
                submitRow
            }
        case .editor:
            VStack(alignment: .leading, spacing: dialogCardSpacing) {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .frame(minHeight: dialogEditorMinHeight)
                    .accessibilityIdentifier(AccessibilityID.chatDialogField)
                submitRow
            }
        }
    }

    private var submitRow: some View {
        HStack {
            Button(submitTitle) { onAnswer(.value(text)) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.chatDialogSubmit)
            cancelButton(answer: .cancelled)
        }
    }

    private func cancelButton(answer: ConversationDialogAnswer) -> some View {
        Button(cancelTitle) { onAnswer(answer) }
            .accessibilityIdentifier(AccessibilityID.chatDialogCancel)
    }
}
