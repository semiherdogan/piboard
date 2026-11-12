import SwiftUI

private let timelineTopPadding: CGFloat = 24
private let timelineBottomPadding: CGFloat = 20
private let composerTopMargin: CGFloat = 8
private let composerBottomMargin: CGFloat = 12
private let composerStackSpacing: CGFloat = 8
private let bottomAnchorID = "conversationBottom"
// How far from the end still counts as "at the bottom", so a rounding gap does not stop the follow.
private let atBottomThreshold: CGFloat = 40
private let displayTogglesSpacing: CGFloat = 4
private let displayToggleSpacing: CGFloat = 4
private let displayToggleHorizontalPadding: CGFloat = 8
private let displayToggleVerticalPadding: CGFloat = 4
private let displayToggleActiveOpacity = 0.15
private let displayToggleEdgePadding: CGFloat = 8
private let thinkingToggleSystemImage = "brain"
private let toolDetailsToggleSystemImage = "wrench.and.screwdriver"
private let thinkingToggleTitle = "Thinking"
private let toolDetailsToggleTitle = "Tool details"
private let toggleOnValue = "On"
private let toggleOffValue = "Off"
private let thinkingToggleHelp = "Cycle how thinking is shown: hidden, collapsed, expanded"
private let toolDetailsToggleHelp = "Show or hide tool arguments and results"
private let dialogOuterPadding: CGFloat = 8
private let errorBannerTitle = "Something went wrong"
private let errorBannerSystemImage = "exclamationmark.triangle.fill"

/// The chat surface of the workspace: the running conversation, or the same "not running" content the terminal shows.
struct ConversationView: View {
    let taskID: UUID
    let isCheckingResume: Bool
    let onResume: () -> Void
    @Environment(AppEnvironment.self) private var environment

    private var task: BoardTask? {
        environment.board.tasks.first { $0.id == taskID }
    }

    var body: some View {
        if let task {
            if let session = environment.processes.conversation(for: taskID) {
                ConversationContent(task: task, session: session, isCheckingResume: isCheckingResume, onResume: onResume)
            } else {
                SessionNotRunningView(task: task, isCheckingResume: isCheckingResume, onResume: onResume)
            }
        } else {
            ContentUnavailableView("Task Not Found", systemImage: "exclamationmark.triangle")
        }
    }
}

private struct ConversationContent: View {
    let task: BoardTask
    let session: ConversationSession
    let isCheckingResume: Bool
    let onResume: () -> Void
    @State private var attachments: [ChatAttachment] = []
    @State private var attachmentError: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if let lastError = session.lastError {
                    BannerView(
                        systemImage: errorBannerSystemImage,
                        title: errorBannerTitle,
                        message: lastError,
                        actionTitle: "Dismiss",
                        action: { session.dismissError() }
                    )
                    .padding(dialogOuterPadding)
                }
                ConversationTimeline(session: session, agent: task.agent)
                VStack(spacing: composerStackSpacing) {
                    if let dialog = session.liveStatus.pendingDialog {
                        // Keyed on the request so a new one starts with its own prefill.
                        ConversationDialogCard(dialog: dialog) { session.answer($0) }
                            .id(dialog.id)
                    }
                    QueuedMessagesRow(messages: session.liveStatus.queuedMessages)
                    ConversationComposer(session: session, agent: task.agent, attachments: $attachments, attachmentError: $attachmentError)
                }
                // Fill the proposal first, or the stack shrinks to its content and the card ends short of the text column.
                .frame(maxWidth: .infinity)
                .frame(maxWidth: ConversationLayout.columnMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ConversationLayout.columnHorizontalPadding)
                .padding(.top, composerTopMargin)
                .padding(.bottom, composerBottomMargin)
            }
            if case .exited(let code) = session.runtimeState {
                SessionExitedOverlay(
                    task: task,
                    agentKind: task.agent,
                    exitCode: code,
                    isCheckingResume: isCheckingResume,
                    onResume: onResume
                )
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            Task { await ChatAttachment.add(files, to: $attachments, error: $attachmentError) }
            return true
        }
    }

}

/// The only chat view that reads the streaming items, so a delta redraws the timeline and nothing around it.
private struct ConversationTimeline: View {
    let session: ConversationSession
    let agent: AgentKind
    @Environment(AppEnvironment.self) private var environment
    @State private var isAtBottom = true
    @State private var columnWidth = ConversationLayout.columnMaxWidth

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        switch row.content {
                        case .item(let item):
                            ConversationItemRow(
                                item: item,
                                thinkingDisplay: environment.preferences.chatThinkingDisplay,
                                showsToolDetails: environment.preferences.chatShowsToolDetails,
                                columnWidth: columnWidth
                            )
                            .padding(.top, row.topSpacing)
                        case .turn(let turn):
                            ConversationTurnView(
                                turn: turn,
                                thinkingDisplay: environment.preferences.chatThinkingDisplay,
                                showsToolDetails: environment.preferences.chatShowsToolDetails,
                                columnWidth: columnWidth,
                                agent: agent
                            )
                            .padding(.top, row.topSpacing)
                        }
                    }
                    // The anchor is the bottom gap itself, so scrollTo(anchor: .bottom) leaves the whole gap visible.
                    Color.clear
                        .frame(height: timelineBottomPadding)
                        .id(bottomAnchorID)
                }
                .frame(maxWidth: .infinity)
                .frame(maxWidth: ConversationLayout.columnMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ConversationLayout.columnHorizontalPadding)
                .padding(.top, timelineTopPadding)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                columnWidth = ConversationLayout.columnWidth(in: width)
            }
            .defaultScrollAnchor(.bottom)
            .onScrollPhaseChange { old, new, context in
                // Only where a user-driven scroll ends counts; growing content and our own scrollTo never flip the flag.
                guard new == .idle, old == .interacting || old == .decelerating else { return }
                let geometry = context.geometry
                let distance = geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
                isAtBottom = distance <= atBottomThreshold
            }
            .onChange(of: session.state.items.last) {
                guard isAtBottom else { return }
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
            .accessibilityIdentifier(AccessibilityID.chatTimeline)
            .overlay(alignment: .topTrailing) {
                ChatDisplayToggles()
            }
        }
    }

    private var rows: [ConversationTimelineLayout.Row] {
        ConversationTimelineLayout.rows(
            for: session.state.items,
            hidesThinking: environment.preferences.chatThinkingDisplay == .hidden,
            isRunning: session.state.isRunning
        )
    }
}

/// Writes the same preferences as Settings, so a change here is global and persisted.
private struct ChatDisplayToggles: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let preferences = environment.preferences
        HStack(spacing: displayTogglesSpacing) {
            toggleButton(
                title: "\(thinkingToggleTitle): \(preferences.chatThinkingDisplay.title)",
                systemImage: thinkingToggleSystemImage,
                isActive: preferences.chatThinkingDisplay != .hidden,
                help: thinkingToggleHelp,
                value: preferences.chatThinkingDisplay.title,
                identifier: AccessibilityID.chatThinkingDisplayToggle
            ) {
                preferences.chatThinkingDisplay = preferences.chatThinkingDisplay.next
            }
            toggleButton(
                title: toolDetailsToggleTitle,
                systemImage: toolDetailsToggleSystemImage,
                isActive: preferences.chatShowsToolDetails,
                help: toolDetailsToggleHelp,
                value: preferences.chatShowsToolDetails ? toggleOnValue : toggleOffValue,
                identifier: AccessibilityID.chatToolDetailsToggle
            ) {
                preferences.chatShowsToolDetails.toggle()
            }
        }
        .padding(displayToggleEdgePadding)
    }

    private func toggleButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        help: String,
        value: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: displayToggleSpacing) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.caption)
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .padding(.horizontal, displayToggleHorizontalPadding)
            .padding(.vertical, displayToggleVerticalPadding)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().fill(Color.accentColor.opacity(isActive ? displayToggleActiveOpacity : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }
}
