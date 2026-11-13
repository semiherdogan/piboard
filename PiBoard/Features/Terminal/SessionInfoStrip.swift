import SwiftUI

private let lastPromptSystemImage = "person"
private let detailSeparator = " · "
private let lastReplySystemImage = "arrowshape.turn.up.left"
private let lastReplyHelpPrefix = "Last reply: "
private let horizontalPadding: CGFloat = 16
private let verticalPadding: CGFloat = 5
private let itemSpacing: CGFloat = 12
// Enough for a sentence; the full message opens on hover.
private let promptMaxWidth: CGFloat = 420
// A preview taller than this stops being glanceable.
private let promptPreviewLength = 600
private let promptPreviewEllipsis = "…"
// Short enough to feel immediate, long enough that sweeping the pointer across does not flash it.
private let promptPreviewDelay: Duration = .milliseconds(150)
private let promptPreviewWidth: CGFloat = 420
private let promptPreviewPadding: CGFloat = 14
private let promptPreviewMaxLines = 20

/// One quiet line above the terminal: what you last asked, the session's size so far and when the agent last replied.
/// Shown for every task with a session, empty until the first turn, so the terminal is never
/// resized when the summary arrives.
struct SessionInfoStrip: View {
    let summary: SessionSummary?
    var showsLastPrompt = true
    /// Scrolls the terminal to the prompt, or opens the find bar when it is not there as typed.
    var findPrompt: (String) -> Void = { _ in }
    @State private var isHoveringPrompt = false
    @State private var showsPromptPreview = false

    var body: some View {
        HStack(spacing: 0) {
            // Zero-width icon in every branch: the reply label's symbol sets the row height, so its arrival changes nothing.
            Label(String(), systemImage: lastReplySystemImage)
                .labelStyle(.iconOnly)
                .frame(width: 0)
                .hidden()
            content
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        // Contain rather than combine, so the prompt button stays a control of its own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.sessionInfoStrip)
    }

    private var content: some View {
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
                if let lastReplyAt = summary.lastAssistantAt {
                    // The minute tick keeps a "Fri 14:30" style label right after midnight without a per-second redraw.
                    TimelineView(.everyMinute) { context in
                        Label(ClockTimestamp.short(lastReplyAt, now: context.date), systemImage: lastReplySystemImage)
                            .lineLimit(1)
                            .monospacedDigit()
                            .help(lastReplyHelpPrefix + ClockTimestamp.full(lastReplyAt))
                    }
                    .layoutPriority(1)
                    .accessibilityIdentifier(AccessibilityID.sessionInfoLastReply)
                }
            } else {
                // Holds the line's height while there is nothing to say yet.
                Label(String(), systemImage: lastPromptSystemImage)
                    .hidden()
                Spacer(minLength: 0)
            }
        }
    }

    private func promptButton(prompt: String, firstLine: String) -> some View {
        Button {
            findPrompt(prompt)
        } label: {
            Label(firstLine, systemImage: lastPromptSystemImage)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: promptMaxWidth, alignment: .leading)
        // A system tooltip waits about a second; this preview opens after a short hover instead.
        .onHover { isHoveringPrompt = $0 }
        .task(id: isHoveringPrompt) {
            guard isHoveringPrompt else {
                showsPromptPreview = false
                return
            }
            try? await Task.sleep(for: promptPreviewDelay)
            guard !Task.isCancelled else { return }
            showsPromptPreview = true
        }
        .popover(isPresented: $showsPromptPreview, arrowEdge: .bottom) {
            Text(preview(of: prompt))
                .font(.callout)
                .lineLimit(promptPreviewMaxLines)
                .padding(promptPreviewPadding)
                .frame(width: promptPreviewWidth, alignment: .leading)
        }
        .accessibilityIdentifier(AccessibilityID.sessionInfoPrompt)
    }

    private func preview(of prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > promptPreviewLength else { return trimmed }
        return String(trimmed.prefix(promptPreviewLength)) + promptPreviewEllipsis
    }
}
