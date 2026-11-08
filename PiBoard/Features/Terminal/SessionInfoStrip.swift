import SwiftUI

private let lastPromptSystemImage = "person"
private let detailSeparator = " · "
private let horizontalPadding: CGFloat = 16
private let verticalPadding: CGFloat = 5
private let itemSpacing: CGFloat = 12
private let promptHelp = "Your last message. Click to find it in the terminal."
private let promptNotFoundTitle = "Not in the terminal anymore"
private let promptPopoverWidth: CGFloat = 420
private let promptPopoverPadding: CGFloat = 14
private let promptPopoverMaxLines = 20

/// One quiet line above the terminal: what you last asked and the session's size so far. Shown for every task with a session, empty until the first turn, so the
/// terminal is never resized when the summary arrives.
struct SessionInfoStrip: View {
    let summary: SessionSummary?
    var showsLastPrompt = true
    /// Scrolls the terminal to the prompt and returns whether it was found there.
    var findPrompt: (String) -> Bool = { _ in false }
    @State private var unfoundPrompt: String?

    var body: some View {
        HStack(spacing: itemSpacing) {
            if let summary, SessionSummaryPresentation.hasStripContent(summary) {
                // The agent's reply is not repeated here: it is right below, in the terminal.
                if showsLastPrompt, let prompt = summary.lastUserText, let firstLine = summary.firstLineOfLastPrompt {
                    promptButton(prompt: prompt, firstLine: firstLine)
                }
                Spacer(minLength: itemSpacing)
                // The figures win over the prompt when the window is narrow.
                Text(SessionSummaryPresentation.stripDetails(summary).joined(separator: detailSeparator))
                    .lineLimit(1)
                    .monospacedDigit()
                    .layoutPriority(1)
            } else {
                // Holds the line's height while there is nothing to say yet.
                Label(String(), systemImage: lastPromptSystemImage)
                    .hidden()
                Spacer(minLength: 0)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        // Contain rather than combine, so the prompt button stays a control of its own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.sessionInfoStrip)
    }

    private func promptButton(prompt: String, firstLine: String) -> some View {
        Button {
            if !findPrompt(prompt) { unfoundPrompt = prompt }
        } label: {
            Label(firstLine, systemImage: lastPromptSystemImage)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .help(promptHelp)
        .accessibilityIdentifier(AccessibilityID.sessionInfoPrompt)
        .popover(isPresented: Binding(get: { unfoundPrompt != nil }, set: { if !$0 { unfoundPrompt = nil } })) {
            VStack(alignment: .leading, spacing: verticalPadding) {
                Text(promptNotFoundTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(unfoundPrompt ?? "")
                    .lineLimit(promptPopoverMaxLines)
                    .textSelection(.enabled)
            }
            .padding(promptPopoverPadding)
            .frame(width: promptPopoverWidth, alignment: .leading)
        }
    }
}
