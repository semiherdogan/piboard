import SwiftUI

private let lastMessageSystemImage = "text.bubble"
private let detailSeparator = " · "
private let horizontalPadding: CGFloat = 16
private let verticalPadding: CGFloat = 5
private let itemSpacing: CGFloat = 12

/// One quiet line above the terminal: what the agent last said, and the session's size so far.
/// Shown for every task with a session, empty until the first turn, so the terminal is never
/// resized when the summary arrives.
struct SessionInfoStrip: View {
    let summary: SessionSummary?

    var body: some View {
        HStack(spacing: itemSpacing) {
            if let summary, SessionSummaryPresentation.hasStripContent(summary) {
                if let lastMessage = summary.firstLineOfLastMessage {
                    Label(lastMessage, systemImage: lastMessageSystemImage)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: itemSpacing)
                // The figures win over the message when the window is narrow.
                Text(SessionSummaryPresentation.stripDetails(summary).joined(separator: detailSeparator))
                    .lineLimit(1)
                    .monospacedDigit()
                    .layoutPriority(1)
            } else {
                // Holds the line's height while there is nothing to say yet.
                Label(String(), systemImage: lastMessageSystemImage)
                    .hidden()
                Spacer(minLength: 0)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.sessionInfoStrip)
    }
}
