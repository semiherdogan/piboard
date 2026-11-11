import SwiftUI

private let timelineTopPadding: CGFloat = 16
private let timelineBottomPadding: CGFloat = 8
private let composerBottomMargin: CGFloat = 12
private let composerStackSpacing: CGFloat = 8
private let bottomAnchorID = "conversationBottom"
private let bottomAnchorHeight: CGFloat = 1
// How far from the end still counts as "at the bottom", so a rounding gap does not stop the follow.
private let atBottomThreshold: CGFloat = 40
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
    @Environment(AppEnvironment.self) private var environment
    @State private var isAtBottom = true
    @State private var columnWidth = ConversationLayout.columnMaxWidth
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
                timeline
                VStack(spacing: composerStackSpacing) {
                    if let dialog = session.state.pendingDialog {
                        // Keyed on the request so a new one starts with its own prefill.
                        ConversationDialogCard(dialog: dialog) { session.answer($0) }
                            .id(dialog.id)
                    }
                    QueuedMessagesRow(messages: session.state.steeringQueue + session.state.followUpQueue)
                    ConversationComposer(session: session, attachments: $attachments, attachmentError: $attachmentError)
                }
                .frame(maxWidth: ConversationLayout.columnMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ConversationLayout.columnHorizontalPadding)
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

    private var timeline: some View {
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
                                columnWidth: columnWidth
                            )
                            .padding(.top, row.topSpacing)
                        }
                    }
                    Color.clear
                        .frame(height: bottomAnchorHeight)
                        .id(bottomAnchorID)
                }
                .frame(maxWidth: ConversationLayout.columnMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ConversationLayout.columnHorizontalPadding)
                .padding(.top, timelineTopPadding)
                .padding(.bottom, timelineBottomPadding)
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
