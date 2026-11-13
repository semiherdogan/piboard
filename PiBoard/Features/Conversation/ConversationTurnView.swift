import SwiftUI

private let turnHeaderSpacing: CGFloat = 6
private let turnChevronCollapsed = "chevron.right"
private let turnChevronExpanded = "chevron.down"
private let turnChevronWidth: CGFloat = 10
private let turnIndent: CGFloat = 16
private let turnLiveTick: TimeInterval = 1
private let workedTitle = "Worked for"
private let turnTimeSeparator = " · "
private let workingTitle = "Working for"
private let turnToggleHelp = "Show or hide the steps"

/// The thinking and tool rows of one agent turn behind a "Worked for" header; a live turn stays open.
struct ConversationTurnView: View {
    let turn: ConversationTimelineLayout.Turn
    let thinkingDisplay: ChatThinkingDisplay
    let showsToolDetails: Bool
    let columnWidth: CGFloat
    let agent: AgentKind
    // The user's choice only; a live turn is open regardless, so it folds by itself when it finishes.
    @State private var isExpanded = false

    private var showsActivity: Bool { turn.isLive || isExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: ConversationTimelineLayout.withinTurnSpacing) {
            if turn.isLive {
                // Nothing to fold while it streams, so no control that would do nothing.
                header
            } else {
                Button {
                    isExpanded.toggle()
                } label: {
                    header
                }
                .buttonStyle(.plain)
                .help(turnToggleHelp)
                .accessibilityIdentifier(AccessibilityID.chatTurnHeader)
            }
            if showsActivity {
                VStack(alignment: .leading, spacing: ConversationTimelineLayout.withinTurnSpacing) {
                    ForEach(turn.activity) { item in
                        ConversationItemRow(
                            item: item,
                            thinkingDisplay: thinkingDisplay,
                            showsToolDetails: showsToolDetails,
                            columnWidth: columnWidth
                        )
                    }
                }
                .padding(.leading, turnIndent)
            }
        }
    }

    private var header: some View {
        HStack(spacing: turnHeaderSpacing) {
            if !turn.isLive {
                Image(systemName: isExpanded ? turnChevronExpanded : turnChevronCollapsed)
                    .frame(width: turnChevronWidth)
            }
            Image(systemName: agent.systemImage)
                .foregroundStyle(.secondary)
            if turn.isLive {
                TimelineView(.periodic(from: turn.startedAt, by: turnLiveTick)) { context in
                    Text("\(workingTitle) \(ConversationDuration.format(context.date.timeIntervalSince(turn.startedAt)))")
                        .monospacedDigit()
                }
                ProgressView()
                    .controlSize(.mini)
            } else {
                // Evaluated only on redraw; there is deliberately no per-header timer, so the clock form can go stale.
                Text("\(workedTitle) \(ConversationDuration.format(turn.duration))\(turnTimeSeparator)\(ClockTimestamp.short(turn.endedAt, now: Date()))")
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
    }
}
